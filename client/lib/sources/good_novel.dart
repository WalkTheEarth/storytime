import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/source.dart';

/// GoodNovel (com.read.goodnovel) — uses the public web API which needs no
/// request signing (the app's RSA-signed API is documented in API.md §4 but
/// the www.goodnovel.com/hwyc endpoints return the same data unsigned).
class GoodNovelSource extends NovelSource {
  GoodNovelSource({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://www.goodnovel.com';
  final http.Client _client;

  @override
  String get id => 'good_novel';

  @override
  String get name => 'GoodNovel';

  /// POST JSON; returns `data` which may be a map or a list depending on endpoint.
  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await _client
        .post(
          Uri.parse('$_base$path'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['success'] != true) {
      throw SourceException('$name: ${json['message'] ?? res.statusCode}');
    }
    return json['data'];
  }

  Future<Map<String, dynamic>> _postMap(String path, Map<String, dynamic> body) async {
    final data = await _post(path, body);
    return data is Map<String, dynamic> ? data : const {};
  }

  Book _book(Map<String, dynamic> j) => Book(
        sourceId: id,
        id: '${j['bookId']}',
        title: (j['bookName'] ?? '').toString(),
        author: j['pseudonym']?.toString(),
        coverUrl: j['cover']?.toString(),
        intro: j['introduction']?.toString(),
      );

  @override
  Future<SearchResult> search(String query, {int page = 1}) async {
    final data = await _postMap('/hwyc/book/search', {
      'keyword': query,
      'current': page,
      'size': 15,
    });
    final records = (data['records'] as List? ?? const []).cast<Map<String, dynamic>>();
    return SearchResult(
      books: records.map(_book).toList(),
      hasMore: records.length >= 15,
    );
  }

  @override
  Future<Book> book(String bookId) async {
    final data = await _postMap('/hwyc/book/detail', {'bookId': bookId});
    return _book(data['book'] as Map<String, dynamic>);
  }

  @override
  Future<List<Chapter>> chapters(String bookId) async {
    final all = <Chapter>[];
    var current = 1;
    while (current <= 100) {
      // /hwyc/chapter/list returns data as a list of volumes.
      final data = await _post('/hwyc/chapter/list', {
        'bookId': bookId,
        'current': current,
        'size': 100,
      });
      final volumes = (data as List? ?? const []).cast<Map<String, dynamic>>();
      if (volumes.isEmpty) break;
      for (final v in volumes) {
        final chs = (v['chapters'] as List? ?? const []).cast<Map<String, dynamic>>();
        for (final c in chs) {
          all.add(Chapter(
            sourceId: id,
            bookId: bookId,
            id: '${c['id']}',
            title: (c['chapterName'] ?? '').toString(),
            locked: c['unlock'] != true,
            index: c['seoChapterName'] != null ? null : null,
          ));
        }
      }
      final last = volumes.last['chapters'] as List? ?? const [];
      if (last.length < 100) break;
      current++;
    }
    // Re-number sequentially (the API does not expose a global index).
    var i = 0;
    return [
      for (final c in all)
        Chapter(
          sourceId: c.sourceId,
          bookId: c.bookId,
          id: c.id,
          title: c.title,
          locked: c.locked,
          index: ++i,
        )
    ];
  }

  @override
  Future<ChapterContent> chapterContent(Chapter chapter) async {
    final data = await _postMap('/hwyc/chapter/detail', {
      'bookId': chapter.bookId,
      'chapterId': chapter.id,
    });
    final text = (data['content'] ?? '').toString();
    return ChapterContent(
      title: (data['chapterName'] ?? chapter.title).toString(),
      paragraphs: const LineSplitter().convert(text),
    );
  }
}
