// Live integration tests — run with:
//   flutter test test/integration_test.dart
// Requires network access. Each source is exercised with its real story code.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:storytime/sources/good_novel.dart';
import 'package:storytime/sources/moto_novel.dart';
import 'package:storytime/sources/novel_master.dart';
import 'package:storytime/sources/plot_novel.dart';

void main() {
  test('Novel Master: story code 538822 -> chapter text', () async {
    final s = NovelMasterSource();
    final r = await s.search('538822');
    expect(r.books, isNotEmpty);
    final book = r.books.first;
    debugPrint('NM book: ${book.title} (${book.id})');
    final chapters = await s.chapters(book.id);
    expect(chapters, isNotEmpty);
    final content = await s.chapterContent(chapters.first);
    debugPrint('NM ch: ${content.title}, paras=${content.paragraphs.length}');
    expect(content.paragraphs, isNotEmpty);
    expect(content.paragraphs.first.length, greaterThan(20));
  });

  test('PlotNovel: story code 684996 -> chapter text', () async {
    final s = PlotNovelSource();
    final r = await s.search('684996');
    expect(r.books, isNotEmpty);
    final book = r.books.first;
    debugPrint('Plot book: ${book.title} (${book.id})');
    final chapters = await s.chapters(book.id);
    expect(chapters, isNotEmpty);
    debugPrint('Plot chapters: ${chapters.length}, first=${chapters.first.title}');
    // Find a free chapter to read.
    final free = chapters.firstWhere((c) => !c.locked, orElse: () => chapters.first);
    final content = await s.chapterContent(free);
    debugPrint('Plot ch: ${content.title}, paras=${content.paragraphs.length}');
    expect(content.paragraphs, isNotEmpty);
  });

  test('MotoNovel: story code 599002 -> chapter text', () async {
    final s = MotoNovelSource();
    final r = await s.search('599002');
    expect(r.books, isNotEmpty);
    final book = r.books.first;
    debugPrint('Moto book: ${book.title} (${book.id})');
    final chapters = await s.chapters(book.id);
    expect(chapters, isNotEmpty);
    debugPrint('Moto chapters: ${chapters.length}, first=${chapters.first.title}');
    final content = await s.chapterContent(chapters.first);
    debugPrint('Moto ch: ${content.title}, paras=${content.paragraphs.length}');
    expect(content.paragraphs, isNotEmpty);
    expect(content.paragraphs.first.length, greaterThan(20));
  });

  test('GoodNovel: story code R67281 -> chapter text', () async {
    final s = GoodNovelSource();
    final r = await s.search('R67281');
    expect(r.books, isNotEmpty);
    final book = r.books.first;
    debugPrint('Good book: ${book.title} (${book.id})');
    final chapters = await s.chapters(book.id);
    expect(chapters, isNotEmpty);
    debugPrint('Good chapters: ${chapters.length}, first=${chapters.first.title}');
    final content = await s.chapterContent(chapters.first);
    debugPrint('Good ch: ${content.title}, paras=${content.paragraphs.length}');
    expect(content.paragraphs, isNotEmpty);
    expect(content.paragraphs.first.length, greaterThan(20));
  });
}
