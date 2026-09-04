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
