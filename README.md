# Shrimphony

A focused Flutter music player for a personal Jellyfin server. It provides a
Spotify-familiar phone experience while keeping playback, queue state, lock-screen
controls, Android Auto, and Apple CarPlay on one audio session.

## Included

- Secure Jellyfin sign-in with the password kept out of storage
- Resume, recently played/added, grouped search, genres, albums, artists,
  playlists, favorites, and full paginated library browsing
- Play, pause, seek, next/previous, shuffle, repeat, Play Next, queue editing,
  and queue/shuffle persistence
- Per-server music-library selection, streaming-quality controls, and library cache
- Song and collection downloads with an offline library and automatic local playback
- Jellyfin playlist creation, renaming, add, and remove controls
- AirPlay, Android system output selection, and handoff to controllable Jellyfin clients
- Background audio, notification/lock-screen controls, and headset controls
- Android Auto media browsing and search through `audio_service`
- Native CarPlay browse and Now Playing templates
- System light/dark mode and accessible labels/touch targets

## Run locally

Tested with Flutter 3.44.2 / Dart 3.12.2. Android builds require Java 17
and Android SDK platform 37; iOS builds require macOS and Xcode.

```sh
git clone git@github.com:HucksleyNash/shrimphony.git
cd shrimphony
flutter pub get
flutter run
```

Enter the Jellyfin base URL, including any reverse-proxy path, for example
`http://192.168.1.20:8096` or `https://music.example.net/jellyfin`.

HTTP works for private IPv4/IPv6 ranges, local hostnames, and `.local` names. Public
HTTP addresses are rejected; use HTTPS outside your trusted LAN. HTTP sends your
Jellyfin credentials and token without transport encryption, so use it only on a
network you trust.

## Vehicle setup

Android Auto uses the declared media browser service automatically. Test it with
the Android Auto Desktop Head Unit or a real vehicle.

CarPlay browsing requires Apple to approve the bundle identifier for the audio-app
entitlement. After approval, select the matching signing team/profile in Xcode;
the entitlement and CarPlay scene are already configured. The simulator can check
layout and compilation, but final acceptance needs a real CarPlay head unit while
the phone is locked.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator
```

Use `flutter run` for the iOS smoke test so the simulator build carries the
Keychain entitlement; an explicitly unsigned build compiles but cannot read secure storage.

Product and interaction decisions are captured in [DESIGN.md](DESIGN.md).

## Reliability release and acceptance

This is a development build. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the
implemented reliability changes and the distribution checklist below. Previous
local audit reports remain available in Git history.

Downloads include durable artwork and collection metadata. Pending/failed jobs survive restarts; jobs continue when the app is reopened, rather than promising OS-scheduled transfers after termination. Settings provides progress, retry/cancel/pause, a Wi-Fi-only policy, storage limits, and bulk removal. Signing out or removing a server deletes that account’s local data. Offline playback reporting is best effort and is not replayed later.

## Distribution checklist

1. Copy `android/key.properties.example` to `android/key.properties`, supply a
   private upload keystore and its passwords, and back up the keystore securely.
   Release builds refuse missing signing configuration by default.
2. Select your Apple signing team/profile in Xcode and obtain the CarPlay audio
   entitlement for `com.thomaskleckner.shrimphony`. Confirm the entitlement in the
   signed archive and review dependency privacy manifests and store metadata.
3. Supply a working public support/privacy destination and store installation links.
   Pass an HTTPS or `mailto:` support address using `--dart-define=SUPPORT_URL=...`.
4. Complete physical-device acceptance: locked-phone Android Auto/CarPlay and
   offline cold starts, audio route changes and interruptions, prolonged background
   playback, gapless playback, full storage, upgrade retention, and screen readers.

After configuring signing and your real support address:

```sh
flutter build appbundle --release --dart-define=SUPPORT_URL=https://your-domain.example/support
flutter build ipa --release --dart-define=SUPPORT_URL=https://your-domain.example/support
```

Outputs are `build/app/outputs/bundle/release/app-release.aab` and `build/ios/ipa/`.
Use the normal `lib/main.dart` entry point without live-test session defines.

For compilation only:

```sh
ORG_GRADLE_PROJECT_allowUnsignedRelease=true flutter build appbundle --release
```

This produces an unsigned bundle, which cannot be submitted as a signed store
release. Keep the normal dependency step enabled for native builds: `--no-pub`
can retain debug-only plugin registration when switching to a release build.

## Integration checks

The default `flutter test` suite includes the launch reproductions, persistence, download failures, offline metadata, account cleanup, and a synthetic 50,000-track refresh. Device checks use Flutter’s installed integration-test runner:

```sh
flutter test integration_test/app_test.dart -d DEVICE_ID
python3 audit/serve_audio_fixtures.py # requires ffmpeg on PATH; run in a second terminal
# Android needs: adb -s DEVICE_ID reverse tcp:8765 tcp:8765
flutter test integration_test/codec_test.dart -d DEVICE_ID
flutter test integration_test/restart_test.dart -d DEVICE_ID --dart-define=RESTART_STAGE=seed --no-uninstall
# The test process exits; force-stop it if it is still running. Preserve app data.
flutter test integration_test/restart_test.dart -d DEVICE_ID --dart-define=RESTART_STAGE=verify
```

`audit/live_server_test.dart` accepts `SHRIMPHONY_LIVE_SESSION` as a path to a private JSON session file. It temporarily edits one favorite and creates its own test playlist, then restores/deletes only those test changes. Opt-in native live tests accept a private `--dart-define-from-file` JSON object whose `LIVE_SESSION` value is a serialized session. `audit/vehicle_runner.dart` uses the same file for manual native vehicle tests. Never distribute a test artifact containing a session; rebuild the normal `lib/main.dart` entry point without test defines afterward.

Keep private live-test JSON files in the ignored `.local/` directory. Environment
files, signing keys, build artifacts, and local audit output are ignored; dependency
lockfiles and the signing template are committed.

## Repository layout and CI

- `lib/`: app UI, Jellyfin client/storage, and playback.
- `android/` and `ios/`: native app projects and vehicle integration.
- `test/`, `integration_test/`, and `audit/`: automated checks and manual test tools.
- `assets/` and [DESIGN.md](DESIGN.md): app artwork and product design decisions.

GitHub Actions runs locked dependency resolution, static analysis, the default
regression suite, and an unsigned Android release bundle build on pushes and pull
requests. iOS simulator builds and physical-device checks run locally using the
commands above. CI does not publish store releases.

The local `website/` directory is an independent Git repository and is excluded
from this app repository. Website deployment is managed separately through its
existing Sites project; publishing it requires access to that project.
