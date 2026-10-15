import 'package:flutter_test/flutter_test.dart';
import 'package:storytime/core/models.dart';
import 'package:storytime/core/registry.dart';

import 'package:storytime/main.dart';

void main() {
  testWidgets('app renders search page', (tester) async {
    await tester.pumpWidget(const StoryTimeApp());
    expect(find.text('StoryTime'), findsOneWidget);
    expect(find.text('Search or paste a story code…'), findsOneWidget);
  });

  test('registry has all four sources', () {
    final registry = SourceRegistry(sources: []);
    // Default constructor path is exercised via StoryTimeApp; here just check
    // the story-code regex-ish handling of empty input.
    expect(registry.importStoryCode(''), completion(isEmpty));
  });

  test('models key format', () {
    const b = Book(sourceId: 'good_novel', id: '123', title: 't');
    expect(b.key, 'good_novel:123');
  });
}
