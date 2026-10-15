# StoryTime

[![CI](https://github.com/WalkTheEarth/storytime/actions/workflows/ci.yml/badge.svg)](https://github.com/WalkTheEarth/storytime/actions/workflows/ci.yml)

A free, open-source Flutter reader that searches **four novel services at
once**, imports books by **story code**, and reads chapters in a clean,
no-accounts-required app.

All four service integrations are reverse-engineered from the official apps
and verified live against production — see [API.md](API.md) for the full
endpoint reference.

## Features

- 🔎 **Unified search** — one query fans out to all four services in parallel
- 📖 **Story-code import** — paste the code from any novel app
  (e.g. `599002`, `R67281`) and get the matching book, whichever service it
  comes from
- 📚 **Full reading flow** — book details, table of contents, chapter reader
- 🔐 **No account needed** — guest sessions are created automatically
  (including MotoNovel's RSA/AES wrapped guest login, implemented in pure Dart)
- 🚫 **No tracking, no ads, no analytics**

## Supported services

| Service | Story code to try | Notes |
|---|---|---|
| MotoNovel | `599002` | signed API, guest login crypto in Dart |
| GoodNovel | `R67281` | |
| Novel Master | `538822` | |
| PlotNovel | `684996` | one-call full book download |

Paid chapters on any service are marked locked and can't be opened — this is a
reader for freely available content.

## Building the app

Prerequisites: [Flutter](https://docs.flutter.dev/get-started/install) (stable
channel) with the Android toolchain set up.

```bash
cd client
flutter pub get
flutter build apk --release
# output: client/build/app/outputs/flutter-apk/app-release.apk
```

Install on a connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or run directly on a device/emulator:

```bash
flutter run
```

CI builds the APK automatically on every push to `main` (download it from the
workflow run's artifacts), and attaches it to a GitHub Release for `v*` tags.

## Using the app

- Type any keyword and hit the search icon (or Enter) to **search** all four
  services.
- Type a **story code** and tap *Import story code* to resolve it directly.
- If something goes wrong (offline, service down), the error is shown under
  the search bar instead of an empty result list.

## Tests

```bash
cd client
flutter test test/widget_test.dart        # hermetic UI/unit tests
flutter test test/integration_test.dart   # LIVE tests against all 4 services
```

The live integration tests use the story codes above and need network access.
CI runs both suites plus a check that the release APK keeps its `INTERNET`
permission.

## Repository layout

```
client/              Flutter app (package:storytime)
  lib/core/          models, source interface, registry (multi-source search)
  lib/sources/       the four service adapters
  lib/ui/            home / book / reader screens
  tool/moto_debug.dart  standalone crypto debug for the MotoNovel login
API.md               reverse-engineered API reference for all four services
work/moto/           Python helpers for the MotoNovel flow (test_moto_novel.py)
.github/workflows/   CI (analyze, tests, APK build + release)
```

## Disclaimer

This project is for personal/educational use. It accesses third-party
services; their terms of service still apply, and all book content belongs to
its authors and platforms. Use responsibly and at your own risk.

## License

No license has been chosen yet — all rights reserved by the author unless a
license file is added.
