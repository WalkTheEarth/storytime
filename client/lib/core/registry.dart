import 'models.dart';
import 'source.dart';
import '../sources/good_novel.dart';
import '../sources/moto_novel.dart';
import '../sources/novel_master.dart';
import '../sources/plot_novel.dart';

/// Registry of all sources + multi-source search and story-code import.
class SourceRegistry {
  SourceRegistry({List<NovelSource>? sources})
      : sources = sources ??
            [
              NovelMasterSource(),
              PlotNovelSource(),
              MotoNovelSource(),
              GoodNovelSource(),
            ];

  final List<NovelSource> sources;

  NovelSource byId(String id) =>
      sources.firstWhere((s) => s.id == id, orElse: () => sources.first);

  /// Search every source in parallel; failures are dropped, not fatal, but
  /// reported into [errors] (one "Source: reason" entry per failed source) so
  /// the UI can distinguish "network broken" from "genuinely no matches".
  Future<Map<NovelSource, SearchResult>> searchAll(
    String query, {
    List<String>? errors,
  }) async {
    final results = await Future.wait(sources.map((s) async {
      try {
        return MapEntry(s, await s.search(query));
      } catch (e) {
        errors?.add('${s.name}: $e');
        return null;
      }
    }));
    return {
      for (final e in results)
        if (e != null && e.value.books.isNotEmpty) e.key: e.value,
    };
  }

  /// Import a story code (e.g. `538822`, `R67281`).
  ///
  /// Every service resolves codes through its normal keyword search, so we
  /// fan out to all sources and return the first hit per source.
  Future<List<Book>> importStoryCode(String code, {List<String>? errors}) async {
    final cleaned = code.trim();
    if (cleaned.isEmpty) return const [];
    final results = await searchAll(cleaned, errors: errors);
    final books = <Book>[];
    for (final r in results.values) {
      books.addAll(r.books.take(1));
    }
    return books;
  }
}
