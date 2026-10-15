# storytime (client)

The Flutter app of the StoryTime project — a multi-source novel reader with
four service adapters, story-code import, and a chapter reader.

See the [repository root README](../README.md) for build instructions, usage,
and testing, and [API.md](../API.md) for the API reference behind the
adapters.

Quick start:

```bash
flutter pub get
flutter test test/widget_test.dart        # hermetic tests
flutter test test/integration_test.dart   # live tests vs all 4 services
flutter build apk --release
```
