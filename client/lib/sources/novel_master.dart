import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/source.dart';

/// Novel Master (com.master.novel) — see API.md §3.
///
/// The live API (verified 2026-10-15) speaks only this dialect:
///   POST /novel/search  {q, offset}      -> `{ret:1, data:{list:[…]}}`
///   POST /novel/chapter {id: chapterId}  -> `{ret:1, data:{novel, chapter, is_vip}}`
///
/// /novel/detail is dead (returns a literal `null` for every id) and the
/// server withholds the chapter list from this app version, so we rebuild the
/// full table of contents from the id layout: each novel's chapters occupy a
/// contiguous block of global chapter ids starting at
/// `novel.first_chapter_id`, with `num = id - first + 1`. A binary search
/// finds the end of the block (~14 requests for a 10k-chapter book).
///
/// Short novels (is_long_story=false) have no readable content on this API —
/// the short-story endpoint was retired server-side.
class NovelMasterSource extends NovelSource {
  NovelMasterSource({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://api.novel-master.com';
  final http.Client _client;

  /// bookId -> raw search item (needed for first_chapter_id / metadata).
  final Map<String, Map<String, dynamic>> _items = {};

  @override
  String get id => 'novel_master';

  @override
  String get name => 'Novel Master';

  /// Human-readable explanation for the API's numeric codes (the raw `msg`
  /// is often Chinese).
  static String _explain(int ret, String msg) {
    switch (ret) {
      case -102:
      case -103:
        return 'bad request (code $ret)';
      case -4001:
        return 'novel not found (code $ret)';
      case -4002:
        return 'content not found (code $ret)';
    }
    final isAscii = msg.codeUnits.every((c) => c < 0x80);
    return isAscii ? '$msg (code $ret)' : 'error code $ret';
  }

  /// Returns null instead of throwing when the API reports ret != 1.
  Future<Map<String, dynamic>?> _tryPost(
      String path, Map<String, dynamic> body) async {
    final res = await _client
        .post(
          Uri.parse('$_base$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final ret = json['ret'];
    if (ret is! num || ret != 1) {
      throw SourceException(
          '$name: ${_explain((ret as num?)?.toInt() ?? 0, '${json['msg']}')}');
    }
    return json['data'] is Map ? json['data'] as Map<String, dynamic> : const {};
  }

  /// Like [_tryPost] but returns null on any API-level failure (used for
  /// block probing where "not found" is an expected answer).
  Future<Map<String, dynamic>?> _probe(
      String path, Map<String, dynamic> body) async {
    try {
      return await _tryPost(path, body);
    } on SourceException {
      return null;
    }
  }

  Book _book(Map<String, dynamic> j) {
    final member = j['member'] as Map<String, dynamic>?;
    final cover = j['cover'] as Map<String, dynamic>?;
    final imgs = (j['imgs'] as List?)?.cast<Map<String, dynamic>>();
    final tags = (j['tags'] as List? ?? const [])
        .map((t) =>
            t is Map ? (t['name'] ?? t['title'] ?? '').toString() : '$t')
        .where((t) => t.isNotEmpty)
        .toList();
    return Book(
      sourceId: id,
      id: '${j['id']}',
      title: (j['title'] ?? '').toString(),
      author: member?['name']?.toString(),
      coverUrl: cover?['url']?.toString() ??
          (imgs != null && imgs.isNotEmpty ? imgs.first['url']?.toString() : null),
      intro: (j['content'] ?? '').toString(),
      tags: tags,
    );
  }

  @override
  Future<SearchResult> search(String query, {int page = 1}) async {
    final data = await _tryPost('/novel/search', {
      'q': query,
      'offset': (page - 1) * 20,
    });
    final list = ((data ?? const {})['list'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final item in list) {
      _items['${item['id']}'] = item;
    }
    return SearchResult(
      books: list.map(_book).toList(),
      hasMore: list.length >= 20,
    );
  }

  @override
  Future<Book> book(String bookId) async {
    final item = _items[bookId];
    if (item == null) {
      throw SourceException('$name: book $bookId not in search cache — '
          'search for it first');
    }
    return _book(item);
  }

  /// Chapter id of the novel's last chapter, found by exponential + binary
  /// search over the contiguous id block. Returns [first] when the novel has
  /// a single chapter.
  Future<int> _findBlockEnd(int first, int bookId) async {
    Future<int> pidOf(int cid) async {
      final d = await _probe('/novel/chapter', {'id': cid});
      final ch = d?['chapter'];
      return ch is Map ? (ch['pid'] as num? ?? -1).toInt() : -1;
    }

    var lo = first; // known to belong (chapter 1)
    var step = 1;
    int? hi;
    while (step <= 65536) {
      if (await pidOf(first + step) == bookId) {
        lo = first + step;
        step *= 2;
      } else {
        hi = first + step;
        break;
      }
    }
    var high = hi ?? first + step;
    while (high - lo > 1) {
      final mid = lo + (high - lo) ~/ 2;
      if (await pidOf(mid) == bookId) {
        lo = mid;
      } else {
        high = mid;
      }
    }
    return lo;
  }

  @override
  Future<List<Chapter>> chapters(String bookId) async {
    final item = _items[bookId];
    if (item == null) {
      throw SourceException('$name: book not in search cache — '
          'search for it first, then open it');
    }
    if (item['is_long_story'] != true) {
      throw SourceException(
          '$name: this is a short story, and the current API no longer '
          'serves short-story content (long novels only)');
    }
    final first = int.parse('${item['first_chapter_id']}');
    final last = await _findBlockEnd(first, int.parse(bookId));
    return [
      for (var i = 0; i <= last - first; i++)
        Chapter(
          sourceId: id,
          bookId: bookId,
          id: '${first + i}',
          title: 'Chapter ${i + 1}',
          index: i + 1,
        ),
    ];
  }

  @override
  Future<ChapterContent> chapterContent(Chapter chapter) async {
    final data = await _tryPost('/novel/chapter', {'id': int.parse(chapter.id)});
    final ch = (data?['chapter'] as Map<String, dynamic>?) ?? const {};
    if (ch['is_unlock'] == false) {
      throw SourceException(
          '$name: chapter ${ch['num'] ?? ''} is VIP-locked '
          '(unlockable only in the official app)');
    }
    final paragraphs = (ch['paragraphs'] as List? ?? const [])
        .map((p) => (p is Map ? (p['content'] ?? '') : '$p').toString())
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) {
      throw SourceException('$name: chapter has no readable content '
          '(locked or unavailable)');
    }
    return ChapterContent(
      title: (ch['name'] ?? chapter.title).toString(),
      paragraphs: paragraphs,
    );
  }
}
