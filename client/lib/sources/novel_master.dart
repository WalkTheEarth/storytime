import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/source.dart';


/// Novel Master (com.master.novel) — React Native app, JSON POST API.
/// See API.md §1. No auth needed for reading.
class NovelMasterSource extends NovelSource {
  NovelMasterSource({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://api.novel-master.com';
  final http.Client _client;

  @override
  String get id => 'novel_master';

  @override
  String get name => 'Novel Master';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _client
        .post(
          Uri.parse('$_base$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ret'] != 1) {
      throw SourceException('$name ${json['ret']}: ${json['msg']}');
    }
    return json['data'] as Map<String, dynamic>;
  }

  Book _book(Map<String, dynamic> j) {
    final member = j['member'] as Map<String, dynamic>?;
    final cover = j['cover'] as Map<String, dynamic>?;
    final imgs = (j['imgs'] as List?)?.cast<Map<String, dynamic>>();
    final tags = (j['tags'] as List? ?? const [])
        .map((t) => t is Map ? (t['name'] ?? t['title'] ?? '').toString() : t.toString())
        .where((t) => t.isNotEmpty)
        .toList();
    return Book(
      sourceId: id,
      id: '${j['id']}',
      title: (j['title'] ?? '').toString(),
      author: member?['name']?.toString(),
      coverUrl: cover?['url']?.toString() ??
          (imgs != null && imgs.isNotEmpty ? imgs.first['url']?.toString() : null),
      intro: j['content']?.toString(),
      tags: tags,
    );
  }

  @override
  Future<SearchResult> search(String query, {int page = 1}) async {
    final data = await _post('/novel/search', {
      'q': query,
      'offset': (page - 1) * 20,
    });
    final list = (data['list'] as List? ?? const []).cast<Map<String, dynamic>>();
    return SearchResult(
      books: list.map(_book).toList(),
      hasMore: list.length >= 20,
    );
  }

  @override
  Future<Book> book(String bookId) async {
    // /novel/chapter with pid returns full novel metadata plus a chapter.
    final data = await _post('/novel/chapter', {'pid': int.parse(bookId), 'chapter': 1});
    return _book(data['novel'] as Map<String, dynamic>);
  }

  @override
  Future<List<Chapter>> chapters(String bookId) async {
    final data = await _post('/novel/chapter', {'pid': int.parse(bookId), 'chapter': 1});
    final novel = data['novel'] as Map<String, dynamic>;
    final chapter = data['chapter'] as Map<String, dynamic>;
    final firstId = '${novel['first_chapter_id'] ?? chapter['id']}';
    return [
      Chapter(
        sourceId: id,
        bookId: bookId,
        id: firstId,
        title: 'Chapter ${chapter['num'] ?? 1}',
        locked: data['is_vip'] == true && chapter['is_unlock'] != true,
        index: 1,
      ),
    ];
  }

  @override
  Future<ChapterContent> chapterContent(Chapter chapter) async {
    final data = await _post('/novel/chapter', {'id': int.parse(chapter.id)});
    final ch = data['chapter'] as Map<String, dynamic>;
    final paragraphs = (ch['paragraphs'] as List? ?? const [])
        .map((p) => (p is Map ? (p['content'] ?? '') : '$p').toString())
        .where((p) => p.isNotEmpty)
        .toList();
    return ChapterContent(
      title: (ch['name'] ?? chapter.title).toString(),
      paragraphs: paragraphs,
    );
  }
}
