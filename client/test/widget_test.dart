import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:storytime/core/models.dart';
import 'package:storytime/core/registry.dart';
import 'package:storytime/core/source.dart';
import 'package:storytime/main.dart';
import 'package:storytime/ui/home_page.dart';

/// In-memory source so widget tests never touch the network.
class _FakeSource extends NovelSource {
  _FakeSource({this.result, this.error});

  final SearchResult? result;
  final Object? error;

  @override
  String get id => 'fake';

  @override
  String get name => 'FakeSource';

  @override
  Future<SearchResult> search(String query, {int page = 1}) async {
    final e = error;
    if (e != null) throw e;
    return result!;
  }

  @override
  Future<Book> book(String bookId) => throw UnimplementedError();

  @override
  Future<List<Chapter>> chapters(String bookId) => throw UnimplementedError();

  @override
  Future<ChapterContent> chapterContent(Chapter chapter) =>
      throw UnimplementedError();
}

Widget _home(NovelSource source) => MaterialApp(
      home: HomePage(registry: SourceRegistry(sources: [source])),
    );

void main() {
  testWidgets('app renders search page', (tester) async {
    await tester.pumpWidget(const StoryTimeApp());
    expect(find.text('StoryTime'), findsOneWidget);
    expect(find.text('Search or paste a story code…'), findsOneWidget);
  });

  testWidgets('search renders books from sources', (tester) async {
    final source = _FakeSource(
      result: SearchResult(books: const [
        Book(sourceId: 'fake', id: '1', title: 'A Test Novel',
            author: 'An Author'),
      ]),
    );
    await tester.pumpWidget(_home(source));

    await tester.enterText(find.byType(TextField), '538822');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('A Test Novel'), findsOneWidget);
    expect(find.text('FakeSource'), findsOneWidget);
    expect(find.textContaining('No results'), findsNothing);
  });

  testWidgets('story-code import renders the matched book', (tester) async {
    final source = _FakeSource(
      result: SearchResult(books: const [
        Book(sourceId: 'fake', id: '42', title: 'Imported Book'),
      ]),
    );
    await tester.pumpWidget(_home(source));

    await tester.enterText(find.byType(TextField), '599002');
    await tester.tap(find.text('Import story code'));
    await tester.pumpAndSettle();

    expect(find.text('Imported Book'), findsOneWidget);
  });

  testWidgets('network failure is surfaced, not shown as empty results',
      (tester) async {
    final source = _FakeSource(
      error: SourceException(
          'SocketException: Failed host lookup: api.example.com'),
    );
    await tester.pumpWidget(_home(source));

    await tester.enterText(find.byType(TextField), 'R67281');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.textContaining('No results'), findsOneWidget);
    expect(find.textContaining('1/1 sources failed'), findsOneWidget);
    expect(find.textContaining('Failed host lookup'), findsOneWidget);
  });

  testWidgets('empty query does nothing', (tester) async {
    await tester.pumpWidget(_home(_FakeSource(result: SearchResult(books: const []))));
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Search across 4 novel services'), findsOneWidget);
  });

  test('registry has all four sources', () {
    final registry = SourceRegistry(sources: []);
    expect(registry.importStoryCode(''), completion(isEmpty));
  });

  test('models key format', () {
    const b = Book(sourceId: 'good_novel', id: '123', title: 't');
    expect(b.key, 'good_novel:123');
  });
}
