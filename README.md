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

Requirements: Flutter 3.44 or newer, Xcode for iOS, and Android Studio/SDK for
Android.

```sh
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

See [RELEASE_NOTES.md](RELEASE_NOTES.md) and [LAUNCH_RELIABILITY_REPORT.md](LAUNCH_RELIABILITY_REPORT.md) for changes, measured checks, and remaining release gates.

Downloads include durable artwork and collection metadata. Pending/failed jobs survive restarts; jobs continue when the app is reopened, rather than promising OS-scheduled transfers after termination. Settings provides progress, retry/cancel/pause, a Wi-Fi-only policy, storage limits, and bulk removal. Signing out or removing a server deletes that account’s local data. Offline playback reporting is best effort and is not replayed later.

Android release builds require `android/key.properties`, using `android/key.properties.example` and a private, backed-up keystore. Never commit signing material. For compilation checks only, `ORG_GRADLE_PROJECT_allowUnsignedRelease=true flutter build apk --release` produces an unsigned artifact; it is not an installable release. Configure the public support URL with `--dart-define=SUPPORT_URL=https://...` or a `mailto:` address before distribution.

The default `flutter test` suite includes the launch reproductions, persistence, download failures, offline metadata, account cleanup, and a synthetic 50,000-track refresh. Device checks use Flutter’s installed integration-test runner:

```sh
flutter test integration_test/app_test.dart -d DEVICE_ID
python3 audit/serve_audio_fixtures.py
# Android needs: adb -s DEVICE_ID reverse tcp:8765 tcp:8765
flutter test integration_test/codec_test.dart -d DEVICE_ID
flutter test integration_test/restart_test.dart -d DEVICE_ID --dart-define=RESTART_STAGE=seed --no-uninstall
# The test process exits; force-stop it if it is still running. Preserve app data.
flutter test integration_test/restart_test.dart -d DEVICE_ID --dart-define=RESTART_STAGE=verify
```

`audit/live_server_test.dart` accepts `SHRIMPHONY_LIVE_SESSION` as a path to a private JSON session file. It temporarily edits one favorite and creates its own test playlist, then restores/deletes only those test changes. Opt-in native live tests accept a private `--dart-define-from-file` JSON object whose `LIVE_SESSION` value is a serialized session. `audit/vehicle_runner.dart` uses the same file for manual native vehicle tests. Never distribute a test artifact containing a session; rebuild the normal `lib/main.dart` entry point without test defines afterward.
