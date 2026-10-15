/// Shared domain models for all novel sources.
library;

class Book {
  const Book({
    required this.sourceId,
    required this.id,
    required this.title,
    this.author,
    this.coverUrl,
    this.intro,
    this.tags = const [],
  });

  /// Adapter that produced this book (e.g. "novel_master").
  final String sourceId;

  /// Source-local book identifier (always kept as string).
  final String id;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? intro;
  final List<String> tags;

  String get key => '$sourceId:$id';
}

class Chapter {
  const Chapter({
    required this.sourceId,
    required this.bookId,
    required this.id,
    required this.title,
    this.locked = false,
    this.index,
  });

  final String sourceId;
  final String bookId;
  final String id;
  final String title;
  final bool locked;

  /// 1-based chapter number when known.
  final int? index;
}

class ChapterContent {
  const ChapterContent({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class SearchResult {
  const SearchResult({required this.books, this.hasMore = false});

  final List<Book> books;
  final bool hasMore;
}
