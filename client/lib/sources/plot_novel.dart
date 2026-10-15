import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/source.dart';

/// PlotNovel (com.plot.novel_app, Flutter) — tourist login + JWT.
/// See API.md §2. Chapter text comes inline in the chapter list response.
class PlotNovelSource extends NovelSource {
  PlotNovelSource({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://server.read.plotread.com/plot-novel';
  final http.Client _client;

  String? _token;
  DateTime? _tokenAt;

  @override
  String get id => 'plot_novel';

  @override
  String get name => 'PlotNovel';

  Future<String> _ensureToken() async {
    // JWT lives ~60 min; refresh defensively after 45.
    if (_token != null &&
        _tokenAt != null &&
        DateTime.now().difference(_tokenAt!) < const Duration(minutes: 45)) {
      return _token!;
    }
    final res = await _client
        .post(
          Uri.parse('$_base/app/touristLogin'),
          headers: const {
            // charset is REQUIRED — without it the server claims empty params.
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          },
          body: {
            'email': 'reader${DateTime.now().millisecondsSinceEpoch % 100000}@example.com',
            'code': '123456',
            'deviceId': _deviceId,
          },
        )
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['success'] != true) {
      throw SourceException('$name login: ${json['message']}');
    }
    _token = (json['result'] as Map<String, dynamic>)['token'] as String;
    _tokenAt = DateTime.now();
    return _token!;
  }

  static final _deviceId =
      'st${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final token = await _ensureToken();
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final res = await _client.get(uri, headers: {'Authorization': token}).timeout(
          const Duration(seconds: 20),
        );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    // Story-code matches return HTTP-level code 201 with success=true.
    if (json['success'] != true) {
      if (json['code'] == 401) _token = null; // force refresh next time
      throw SourceException('$name: ${json['message']}');
    }
    return json['result'] as Map<String, dynamic>? ?? const {};
  }

  @override
  Future<SearchResult> search(String query, {int page = 1}) async {
    final result = await _get('/app/novel/searchNovel', {
      'keyword': query,
      'pageNo': '$page',
      'pageSize': '20',
    });
    final records = (result['records'] as List? ?? const []).cast<Map<String, dynamic>>();
    return SearchResult(
      books: records.map(_book).toList(),
      hasMore: records.length >= 20,
    );
  }

  Book _book(Map<String, dynamic> j) => Book(
        sourceId: id,
        id: '${j['id']}',
        title: (j['enName'] ?? j['name'] ?? '').toString(),
        author: j['authorName']?.toString(),
        coverUrl: j['coverImage']?.toString(),
        intro: (j['introduction'] ?? j['description'] ?? j['novelDescription'])?.toString(),
      );

  @override
  Future<Book> book(String bookId) async {
    final result = await _get('/app/chapter/chapterListByNovel', {
      'novelId': bookId,
      'pageNo': '1',
      'pageSize': '1',
    });
    return Book(
      sourceId: id,
      id: bookId,
      title: (result['novelName'] ?? '').toString(),
      coverUrl: result['novelCover']?.toString(),
      intro: result['novelDescription']?.toString(),
    );
  }

  /// The chapter list endpoint returns the COMPLETE list in one response —
  /// paging params are ignored (verified live; the current catalog tops out
  /// at 20 chapters per book, matching the server's window size).
  Future<List<Map<String, dynamic>>> _fullList(String bookId) async {
    final result = await _get('/app/chapter/chapterListByNovel', {
      'novelId': bookId,
      'pageNo': '1',
      'pageSize': '100',
    });
    return (result['chapters'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Chapter>> chapters(String bookId) async {
    final list = await _fullList(bookId);
    return [
      for (final c in list)
        Chapter(
          sourceId: id,
          bookId: bookId,
          id: '${c['id']}',
          title: (c['chapterTitle'] ?? 'Chapter ${c['chapterNo']}').toString(),
          locked: c['unlocked'] == false && c['izFree'] != 1,
          index: c['chapterNo'] as int?,
        ),
    ];
  }

  @override
  Future<ChapterContent> chapterContent(Chapter chapter) async {
    // Content is embedded in the (complete) chapter list; refetch to find it.
    final list = await _fullList(chapter.bookId);
    final match = list.cast<Map<String, dynamic>?>().firstWhere(
          (c) => '${c!['id']}' == chapter.id,
          orElse: () => null,
        );
    if (match == null) throw SourceException('$name: chapter ${chapter.id} not found');
    final text = (match['chapterContent'] ?? '').toString();
    if (text.isEmpty) {
      throw SourceException('$name: chapter is locked or empty');
    }
    return ChapterContent(
      title: (match['chapterTitle'] ?? chapter.title).toString(),
      paragraphs: const LineSplitter().convert(text),
    );
  }
}
