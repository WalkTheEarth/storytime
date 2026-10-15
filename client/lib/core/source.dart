import 'models.dart';

/// A novel source backed by one of the four services (see API.md).
abstract class NovelSource {
  /// Stable id used in models and settings (e.g. "novel_master").
  String get id;

  /// Human-readable name shown in the UI.
  String get name;

  /// Search by keyword. Story codes resolve through plain search on every
  /// service, so [query] may also be a story code.
  Future<SearchResult> search(String query, {int page = 1});

  /// Book detail (metadata) for a source-local book id.
  Future<Book> book(String bookId);

  /// Full table of contents, in reading order.
  Future<List<Chapter>> chapters(String bookId);

  /// Chapter text. [chapter] must come from [chapters].
  Future<ChapterContent> chapterContent(Chapter chapter);
}

/// Thrown when a source reports an error.
class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}
