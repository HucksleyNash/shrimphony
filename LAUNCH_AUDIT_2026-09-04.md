# Shrimphony launch and competitive feature audit

Audited September 4, 2026 · App version 1.0.0+1 · Android and iOS

**Recommendation: finish a reliability release, then a focused feature-parity release. Shrimphony has a useful foundation, but it is not ready to claim “the most capable Jellyfin music player.”** Matching the main everyday workflows is achievable with the existing app. Matching the broadest competitors also requires substantial audio, casting, offline, and integration work.

The strongest initial positioning is **a dependable Jellyfin music player across phone, car, and offline listening**. That is a proposed direction, not a verified market advantage. Car integration is already available elsewhere; its reliability and consistency would need to distinguish Shrimphony.

## Scope and evidence

I inspected the Flutter application, Jellyfin API/client and storage code, playback handler, Android integration, native CarPlay bridge, existing tests, design document, and launch website. The actual project is [Shrimphony](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt); the originating task was attached to a different workspace.

This is a source-backed feature and launch-readiness audit with compilation and targeted reproductions. It is **not** a completed live-server, accessibility, audio-quality, or vehicle certification exercise. No personal music server, physical phone, receiver, or head unit was used. Competitor capabilities below are developer-documented, not independently device-tested.

The market sample covers 11 products across Jellyfin mobile, Navidrome/Subsonic mobile, and desktop. Desktop features inform the capability ceiling but do not automatically become mobile launch requirements. Beta features and documented limitations are identified. Missing documentation is not treated as proof that a competitor lacks a feature.

The existing [DESIGN.md](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/DESIGN.md) explicitly excludes lyrics, EQ, crossfade, widgets, and several other advanced features from v1. The new ambition changes that product scope; these omissions were intentional in the earlier plan.

### Verification completed

| Check | Result | What it establishes |
|---|---|---|
| `flutter analyze --no-pub` | Passed, no issues | Static analysis |
| `flutter test --no-pub` | All 16 existing tests passed | Current helper, storage, URL and mocked API contracts |
| `flutter build apk --debug --no-pub` | Passed | Android debug compilation |
| `flutter build ios --simulator --no-pub` | Passed | iOS simulator compilation |
| Two additional launch-contract checks | Both failed as expected | Reproduced album ordering and incomplete artist action inputs |

Despite its filename, the existing `test/widget_test.dart` contains ordinary tests, with no `testWidgets` cases. It does not establish that phone UI flows, real audio playback, CarPlay, or Android Auto work end to end.

The isolated [launch contract checks](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/audit/launch_contract_test.dart) use a local mock HTTP server and are outside the default test directory. Run from the app project:

```sh
flutter test --no-pub audit/launch_contract_test.dart
```

They express expected launch behavior and currently fail. When fixing the artist workflow, retain a ten-track preview if desired and adapt that check to the full collection action; displaying every track is not required.

## Competitors and the bar they set

| Product | Platform / server scope | Documented capabilities relevant to this audit | Implication |
|---|---|---|---|
| **Symfonium** | Android; Jellyfin and Navidrome among many sources | Offline caching, smart playlists, multiple providers, Chromecast/DLNA/Sonos, advanced EQ/AutoEQ, high-resolution output and extensive customization. [Developer site](https://www.symfonium.app/) | The broadest Android benchmark in this sample. Full breadth parity is a major product effort. |
| **Finamp** | Android/iOS; Jellyfin, plus desktop builds | Gapless playback, lyrics, normalization, transcoded downloads and playback reporting. Its beta includes CarPlay, Android Auto, Siri, customizable Home and AudioMuse integration. [README](https://github.com/finamp-app/finamp), [release history](https://github.com/finamp-app/finamp/releases) | Closest direct baseline. The latest release observed was **1.0.1-beta**, September 2; distinguish beta access from stable-store availability. [Version](https://github.com/finamp-app/finamp/releases/tag/1.0.1-beta) |
| **Jellify** | Android/iOS; Jellyfin | Library and playlist management, Instant Mix, offline playback, storage manager, gapless playback, both car systems and Google Cast. The README describes Cast as early-stage; later release notes describe integration improvements. [Feature list](https://github.com/Jellify-Music/App/blob/main/README.md), [1.2.0 release](https://github.com/Jellify-Music/App/releases/tag/1.2.0) | Discovery and storage controls are already direct-competitor expectations. Do not count its roadmap as shipped functionality. |
| **Fintunes** | Android/iOS; Jellyfin | Search, streaming, downloads, system appearance, AirPlay and Chromecast. [Developer site](https://www.fintunes.app/) | Even a deliberately minimal competitor advertises Chromecast. |
| **Headroom** | Android/iOS beta; Jellyfin, Navidrome and other servers | Advertises gapless/crossfade, ReplayGain, parametric EQ/AutoEq, resumable downloads, radio, lyrics, car support, Chromecast, widgets and SyncPlay. Its site identifies beta distribution and pending Android store review. [Developer site](https://headroommusic.app/) | An emerging breadth competitor. Treat its claims as a beta benchmark, not proven mature execution. |
| **Amperfy** | iOS/iPadOS/macOS; Subsonic/Ampache, including Navidrome | Multiple accounts, offline mode, CarPlay, gapless playback, Siri/App Intents, EQ, ReplayGain, sleep timer, ratings, scrobbling, podcasts and radio. [Feature list](https://github.com/BLeeEZ/amperfy) | Useful Apple ecosystem benchmark beyond Jellyfin. |
| **play:Sub** | Apple platforms; Subsonic/Navidrome | Automatic caching and prefetch, offline browsing, AirPlay, CarPlay, Chromecast, lyrics, ReplayGain, sleep timer, widgets and bookmarks are documented across its site and store history. [Developer site](https://michaelsapps.dk/playsubapp/), [store listing](https://apps.apple.com/us/app/play-sub-music-streamer/id955329386) | Mature offline behavior and convenience controls are material gaps. |
| **Substreamer** | Android/iOS; Subsonic/Navidrome | Offline recovery/search, storage controls, ratings, playlists, smart mixes, offline scrobbling and listening statistics. Its recent store notes also list car support, casting, EQ/ReplayGain, gapless/crossfade and playback caching. [Developer site](https://substreamer.org/), [store notes](https://apps.apple.com/us/app/substreamer/id1012991665) | Strong benchmark for offline operations and rediscovery. |
| **Tempus** | Android; Subsonic/Navidrome; fork of Tempo | Gapless, ReplayGain, mixes, EQ, scrobbling, widgets, radio and multiple libraries. Android Auto and rudimentary Chromecast require the Google-enabled build. Offline mode is documented as still developing, with multi-server limitations. [README](https://github.com/eddyizm/tempus) | Useful Android feature benchmark with explicit distribution and maturity caveats. |
| **Feishin** | Desktop/web; Jellyfin, Navidrome/OpenSubsonic | MPV/web playback, lyrics, server scrobbling and a Navidrome smart-playlist editor. Desktop is recommended; the web backend has a different feature envelope. [README](https://github.com/jeffvli/feishin) | Benchmark advanced browsing and playlist tools; do not require desktop parity for phone launch. |
| **Supersonic** | Desktop; Jellyfin/Subsonic/Navidrome | Gapless MPV playback, ReplayGain, EQ, lyrics, DLNA, filters, alternate server URLs and downloads. Full offline mode is explicitly still planned. [README](https://github.com/dweymouth/supersonic) | Downloads and a complete offline experience must be evaluated separately. |

Selection was informed by the official [Jellyfin client directory](https://jellyfin.org/downloads/clients/all/) and [Navidrome app directory](https://www.navidrome.org/apps/). Versions observed through publisher release APIs included Jellify 1.2.10, Tempus 4.26.1, Amperfy 2.1.1, Feishin 1.15.1 and Supersonic 0.22.1. Feature lists can describe development branches; installation-specific parity must be checked against the release actually tested.

## Shrimphony feature inventory and gap matrix

**Implemented** means an application path exists in the inspected source; it does not imply a hardware pass. **Partial** means a material part of the workflow is absent or defective. **Verify** means the necessary engine/platform wiring exists but its behavior needs execution. **Missing** means no implementation was found.

Priority: **R** = release correctness/readiness; **C** = competitive everyday functionality; **A** = advanced capability; **E** = expansion beyond the initial Jellyfin phone product. Benchmark names refer to the linked evidence above; the column provides positive examples, not a complete yes/no verdict for every competitor.

| Capability | Shrimphony today | Benchmark / recommended disposition |
|---|---|---|
| Jellyfin sign-in; secure token persistence | Implemented; password not saved | Preserve. |
| Saved servers and accounts | Implemented; one active server | Useful baseline; preserve. |
| Per-server music-library selection | Implemented | Preserve; exercise with overlapping libraries. |
| Reverse-proxy subpaths; local HTTP / public HTTPS | Implemented with URL tests | R: test actual proxy/network paths. |
| Quick Connect | Missing | A: easier Jellyfin onboarding. |
| Alternate LAN/WAN addresses for one server | Missing | A: Supersonic-style connection convenience. |
| Navidrome/OpenSubsonic backend | Missing; all API operations are Jellyfin-specific | E: separate backend project, not required for Jellyfin leadership. |
| Unified cross-server library/search | Missing | E: Symfonium benchmark. Saved server switching is not aggregation. |
| Albums, artists, tracks, genres, favorites | Implemented | Preserve. |
| Correct album/disc sequencing | Defective | R: fix shared sort handling. |
| Artist Play / Shuffle / Download All | Partial; detail screen only supplies ten songs | R: use full artist collection for actions. |
| Grouped search | Implemented | Preserve. |
| Search “see all” / pagination | Missing; combined results capped at 60 | C: add typed result expansion. |
| Search downloaded music offline | Missing | C: query locally available metadata. |
| Advanced library filtering / alphabetical jump | Missing beyond A–Z, Z–A, newest and entity filters | A: common power-user benefit. |
| Rich music metadata | Partial; basic artist/album/year/disc data | A: add useful track format, album-artist and credit details when provided. |
| Play/pause/seek/previous/next | Implemented | R: verify interruptions, buffering and route changes. |
| Background / headset / lock-screen controls | Implemented wiring | R: physical-device tests required. |
| Gapless playback | Verify; uses just_audio playlists | R/C: test actual direct, transcoded and downloaded albums. |
| Shuffle and repeat | Implemented with queue-semantics concerns | R: visible order and Play Next must match what plays. |
| Queue reorder/remove/clear | Implemented | R: verify edits during playback and under shuffle. |
| Complete queue restoration | Partial; only 100 tracks restored | R: preserve all user queue entries and shuffle state. |
| Save queue as playlist | Missing | C: reuse existing playlist creation API. |
| Queue album/artist/playlist without replacing playback | Missing in phone action menu | C: collection actions should reuse queue handling. |
| Playback speed | Missing UI/handler command; engine supports it | C/A: inexpensive useful control after persistence is defined. |
| Sleep timer / end-of-track stop | Missing | C: Amperfy/play:Sub benchmark. |
| ReplayGain / volume normalization | Missing | C: Finamp/Amperfy/Tempus benchmark. |
| EQ / headphone profiles | Missing | A: basic Android EQ is easier than cross-platform EQ. |
| Crossfade | Missing | A: requires audio-path work and interaction testing. |
| True hi-res / exclusive USB / DSD output | No dedicated implementation or evidence | E: Symfonium/Supersonic audio ceiling; do not claim from file format alone. |
| Synced and plain lyrics | Missing | C: major Finamp and Navidrome-player gap. |
| Quality selection | Implemented global bitrate preference | C: distinguish Wi-Fi/mobile/download settings; existing queued URIs retain their chosen parameters. |
| Format-aware direct play / fallback | Partial; common stream formats advertised, no platform-specific capability policy | R: validate codec/container combinations on both platforms. |
| Track/album/artist/playlist downloads | Implemented | R: artist detail action discrepancy; portable originals or AAC fallback. |
| Durable background download jobs | Missing; in-memory serial queue | C: survive suspension/restart and offer recovery. |
| Download progress, retry, cancel, pause | Partial; current item and waiting count, no byte progress or full job controls | C: essential for large collections. |
| Cache limits, bulk deletion, Wi-Fi-only downloads | Missing; total download size is shown | C: complete storage management. |
| Automatic playback cache / look-ahead | Missing | A: play:Sub/Substreamer benchmark. |
| Fully offline album/playlist browsing and artwork | Partial; library snapshot and song files, detail/search still call server | R/C: make the whole downloaded workflow local. |
| Downloaded tracks from car without server access | Defective path | R: car selection fetches the track from the API first. |
| Sync changed playlists/favorites to downloads | Missing | A: managed offline collections. |
| Favorite/unfavorite | Implemented online | C: optional offline mutation queue after online correctness. |
| Playlist create/rename/add/remove/reorder | Implemented | Preserve; test permissions and duplicate entries on a real server. |
| Playlist delete, bulk editing, artwork/description/privacy | Missing UI | C/A: prioritize delete and bulk add first. |
| Smart/dynamic playlists | Missing | A: Symfonium/Feishin/Substreamer benchmark; backend semantics differ. |
| Instant Mix / song radio | Partial; API and vehicle actions exist, phone actions absent | C: high-value reuse opportunity. |
| Continuous autoplay / similar artists | Missing | A: opt-in continuation; use server-supported recommendations. |
| AudioMuse sonic recommendations | Missing | A: optional server integration after basic mixes work. |
| Recently played / recently added / rediscovery | Implemented; random album rediscovery | Preserve; do not describe random albums as personalized recommendations. |
| Listening history, play counts, listening statistics | Partial; recent list and reporting only | A: add only after reporting is trustworthy. |
| Offline playback-report replay / scrobbling | Missing; failed reports become events and are not persisted | C: verify server plugins, then support reconnect behavior. |
| Direct Last.fm / ListenBrainz account integration | Missing | A: avoid duplicating scrobbles if server integration covers the need. |
| AirPlay / Bluetooth / Android output selection | Native wiring exists | R: test outputs; older Android opens Bluetooth settings. |
| Chromecast | Missing | A, or C if casting is a launch promise; Fintunes already offers it. |
| DLNA / UPnP / Sonos | Missing | A/E: advanced casting; separate from Chromecast. |
| Jellyfin remote-client handoff | Implemented, one-way send then pause locally | A: persistent remote controls and state following are absent. |
| Jellyfin SyncPlay / shared listening | Missing | A: Headroom advertises beta support. |
| Android Auto browsing and search | Partial | R: root routes omit Downloads/Playlists; lists capped; verify voice matching. |
| Native CarPlay browsing / Now Playing | Partial | R: entitlement and hardware validation, offline path, artwork and discoverability. |
| Siri media requests / App Intents | Missing | C/A: Finamp beta and Amperfy raise this bar. |
| System dark/light themes | Implemented | Preserve. |
| User-selected themes / artwork colors | Missing | A: cosmetic parity after playback reliability. |
| Tablet layout / landscape optimization | Basic responsive sizing only | A: Substreamer/Amperfy benchmark. |
| Screen-reader labels / large-text behavior | Some semantics/tooltips exist; runtime unverified | R: navigation, queue and transport checks. |
| Localization | Missing; strings embedded in English | A: support requested markets incrementally. |
| Widgets / watch clients | Missing | A/E: widgets first; watch apps are separate surfaces. |
| Sharing / deep links / playlist import-export | Missing | A: useful ecosystem convenience; respect backend support. |
| Podcasts / audiobooks / radio | Missing | E: separate from core Jellyfin music readiness. |
| In-app support, diagnostics, privacy, licenses | Missing routes in Settings | R: actionable support and accurate privacy controls before release. |

Source map: [API, preferences and storage](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart), [phone UI](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/app.dart), [audio and vehicle logic](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/playback.dart), [native CarPlay](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/ios/Runner/CarPlaySceneDelegate.swift), [native Android](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/android/app/src/main/kotlin/com/thomaskleckner/shrimphony/MainActivity.kt).

## Concrete release findings

### 1. Album order is lost in the shared merge function — reproduced

The server is asked for disc/track ordering, but `_merge` only understands date-created, date-played and production-year sorting; every other sort is replaced with title ordering. A three-song, two-disc response came back as track 2, disc 2 track 1, then track 1. This affects phone and vehicle album playback, and also disrupts requested artist/genre grouping.

**Fix:** preserve authoritative server order for a single collection; when merging multiple libraries, apply the complete requested sort keys. Do not add compensating sorts independently to each screen. [Shared merge](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart:1358), [album request](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart:1191).

### 2. Artist actions operate on a ten-song preview — reproduced

`AppController.children` takes ten artist songs, then adds album objects. The detail screen derives Play, Shuffle and “Download all songs” from the audio subset of those same children. The audit returned ten action inputs for a twelve-song artist. The artist context-menu download already fetches all songs, so behavior differs between entry points.

**Fix:** keep previews separate from full collection actions and reuse the existing complete artist query. [Preview](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart:1707), [detail actions](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/app.dart:1558).

### 3. Queue persistence silently discards tracks — confirmed in source

Restoration calls `boundedQueueWindow` with a default maximum of 100. For a 500-track queue at index 250, only indices 240–339 are restored. The original shuffle permutation is then discarded, and a subsequent save persists the shortened queue. The rest is not restored by a retained paging cursor.

**Fix:** persist the complete logical queue while bounding only the loaded audio sources if performance requires it. First measure whether ordinary queues need that optimization. [Restore path](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/playback.dart:986).

### 4. Offline support breaks across entry points — confirmed paths; hardware test outstanding

A phone download row can use local audio, but search and collection detail loading still require the server. A car download row routes through `playFromMediaId`, which calls `api.item(id)` before selecting its local file. Downloaded metadata cannot rescue that request. The Android Auto root has no reachable Downloads or Playlists category: its Library submenu exposes only albums, artists and genres.

If the library snapshot is absent but downloads survive, `_AppRoot` does not count downloads when deciding whether to show the connection error screen. Phone artwork is fetched through `Image.network`, with no durable downloaded-artwork path.

**Fix:** resolve downloaded metadata before network access, expose downloaded collections/search, and make Downloads reachable on both car systems. A previously downloaded track must start in airplane mode after process termination. [Car resolution](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/playback.dart:811), [root state](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/app.dart:109), [search/detail](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart:1701).

### 5. Shuffle order and explicit queue intent can diverge — source-backed risk

The queue UI displays the stored list. Playback can use a separate native shuffle permutation. Play Next inserts at the next physical index, while the installed just_audio shuffle implementation inserts new entries into its shuffled order at a random position. Collection shuffle also materializes an order and then enables another native shuffle.

**Fix:** define one authoritative play order and preserve explicit user insertions. Acceptance: while shuffled, Play Next is literally next; the next displayed queue item is the next heard item; reorder and repeat remain coherent. Verify through the real handler, not only the shuffle helper. [Play Next](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/playback.dart:304), [shuffle](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/playback.dart:439).

### 6. iOS system artwork uses an Android URI — source-backed integration defect

`vehiclePlayingMediaItem` always supplies a `content://...artwork` URI. The installed audio_service 0.18.19 bypasses artwork downloading for that scheme; its Apple implementation expects an `artCacheFile`. No corresponding iOS file is supplied. The phone UI works around this through `remoteArtUri`, but system Now Playing does not use that UI fallback.

**Fix:** use the Android provider only on Android and supply authenticated remote or cached-file artwork on iOS. Verify lock screen and CarPlay on device. [Metadata construction](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/playback.dart:94).

### 7. Downloads and playback errors need recovery — confirmed omissions

The download queue lives only in memory. There is no resumable job record, durable retry list, cancellation control, storage cap or Wi-Fi policy. Completed audio records are persisted and partial files are excluded, which is a useful foundation.

Playback errors are emitted through playback state, while the main transport renders play/pause without a dedicated failure/retry presentation. Reporting and queue-loading custom events have no phone UI subscriber. A build pass cannot establish graceful network recovery.

**Fix:** persist pending jobs and actionable failures; support retry/cancel and interrupted app lifecycle before advertising dependable bulk offline use. Add visible playback Retry/Skip behavior without hiding the current song. [Download worker](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart:1757), [transport](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/app.dart:2023).

### 8. Full-library refresh is a scaling bottleneck — source-backed risk, not a measured failure

Refresh waits for all pages of albums, artists, songs, playlists, favorites and genres before publishing fresh results. Pagination prevents truncation but does not make the initial screen incremental. The phone “Shuffle your library” action also loads all songs into the player, while the vehicle implementation has a separate paging strategy.

**Fix:** expose cached data immediately, publish useful initial results before the complete scan, and reuse a coherent shuffle path. Profile a 50,000-track library before choosing a database or rewriting state management. [Refresh](/Users/thomaskleckner/Documents/development/jellyfinmusicplayergpt/lib/jellyfin.dart:1621).

### 9. Distribution and support are unfinished — confirmed configuration gaps

Android release builds are configured with the debug signing key. The iOS project declares a CarPlay entitlement and signing team, but a simulator build does not prove the entitlement is granted in a distribution profile. Apple describes the CarPlay entitlement request process in its [developer guidance](https://developer.apple.com/carplay/); Flutter documents [Android release signing](https://docs.flutter.dev/deployment/android).

The website has a privacy page, but no App Store/Play Store install buttons or actual support destination. Its privacy contact sends users to the store listing, which the site does not link. The app Settings lacks About, privacy, licenses and support routes. Removing a server does not erase its downloaded audio/library files, and there is no complete per-server data cleanup UI.

The Flutter app root has no Git repository in the inspected project; only the website has one. Establish a recoverable release baseline and preserve the signing key before distribution. Do not overwrite or fold the website repository into another history casually.

**Fix:** release signing, entitlement verification, a real beta/install/support path, accurate data-removal controls, release notes and a reproducible source baseline. Review the built archive and dependency privacy declarations rather than inferring store compliance from individual source files.

## Shortest practical implementation path

Effort is relative: **S** = localized change; **M** = several coordinated paths; **L** = substantial platform/state work; **XL** = a separate product capability. These are scope estimates, not delivery-date promises.

| Order | Deliverable | Effort | Reuse / completion criterion |
|---|---|---|---|
| 1 | Correct album/artist actions, queue restoration and shuffle semantics | M | Fix shared client/handler logic. Preserve disc order, every queue item and explicit Play Next intent. |
| 2 | Offline phone and car continuity; correct iOS artwork | M–L | Reuse download manifest and existing vehicle routes. Cold-start airplane-mode playback succeeds without a metadata request. |
| 3 | Playback error recovery and durable download management | L | Extend current store/worker; use platform background transfer facilities where required. Kill/relaunch, retry/cancel and disk-full behavior retain valid data. |
| 4 | Release packaging and hardware acceptance | M plus external approval/testing time | Signed release builds; approved CarPlay profile if claimed; install/support/privacy routes; all release checks below pass. |
| 5 | Phone Instant Mix, Go to Album/Artist, save queue, playlist delete/bulk add | S–M | Existing item IDs, Instant Mix, queue and playlist endpoints cover most of the work. No recommendation service required. |
| 6 | Plain/synced lyrics and offline lyric retention | M | Use Jellyfin-provided lyrics first; synchronized lines seek and remain available for downloads. |
| 7 | Loudness normalization and verified gapless behavior | M–L | Preserve the engine; support available server loudness data, missing-data fallback and clipping handling. Test direct and transcoded paths independently. |
| 8 | Sleep timer, speed and independent quality policies | S–M | Engine controls/native mechanisms; persist settings; timer works while locked. |
| 9 | Search expansion, offline search, storage controls and large-library responsiveness | M–L | Reuse metadata; measure before adding a database. No 60-result dead end; cached browsing remains responsive. |
| 10 | Chromecast and Siri integration | L | Native SDK/intent integration with shared queue. Validate receiver connectivity, authentication and reconnection; direct handoff is not sufficient. |
| 11 | Smart playlists, autoplay, reliable scrobbling and optional sonic recommendations | L | Start with existing server data and deterministic filters; optional integrations should degrade gracefully. |
| 12 | Cross-platform EQ, crossfade, DLNA and persistent remote control | L–XL | Prototype the actual audio/receiver path before committing to UI breadth. |
| 13 | Navidrome, desktop/watch, unified libraries and specialist hi-res output | XL | Separate milestones after Jellyfin reliability and core parity. |

**Release sequence:** steps 1–4 support a responsible focused launch or wider beta. Steps 5–9 make that launch more competitive with everyday music clients. Steps 10–12 support a stronger capability claim. Step 13 broadens the product; it is not necessary merely because Navidrome clients were used as benchmarks.

Several features do not require new infrastructure:

- Jellyfin already supports synchronized and unsynchronized lyric files. Use its data before adding an external lyric lookup dependency. [Music documentation](https://jellyfin.org/docs/general/server/media/music/)
- The installed just_audio engine supports gapless playlists and speed controls. Treat gapless as something to validate and repair, not automatically a missing engine feature. Its EQ support is Android-specific, so iOS EQ is not a settings-only change. [Engine capabilities](https://pub.dev/packages/just_audio)
- Instant Mix and playlist creation already exist in Shrimphony. Expose and reuse them.
- Start smart collections with rules over available library data. Keep AudioMuse optional.
- Preserve secure storage and the single audio session. There is no demonstrated need for a framework rewrite or a Shrimphony cloud service.

Navidrome is a distinct protocol implementation, not another Jellyfin URL. If added, implement the specific second backend and discover supported OpenSubsonic capabilities; lyrics, reporting and other extensions vary by server. Avoid assuming server-side playlist editing, ratings, or scrobbling are identical across backends. [OpenSubsonic extensions](https://opensubsonic.netlify.app/docs/extensions/)

## Launch acceptance and a defensible “most functionality” target

Do not turn a count of buttons into a parity percentage. For the next milestone, use a frozen checklist: **all release-critical journeys pass on both target platforms, and at least 90% of a separately agreed everyday-capability set passes end to end.** The 90% threshold is a proposed release target, not a measured result from this audit.

The everyday set should include complete library/search access, correct album/artist/playlist playback, queue editing and restoration, shuffle/repeat, background and car controls, downloaded browsing/playback, recoverable downloads, lyrics, normalization, gapless, sleep timer, quality controls, useful mixes and playlist management. Casting/Siri should be explicit platform commitments if included in marketing. Advanced DSP, watch apps and unrelated media should not dilute this denominator.

| Journey | Required evidence before release |
|---|---|
| Fresh and returning sign-in | Local address, HTTPS, reverse-proxy subpath, bad credentials, expired token, server switch and unavailable server recover cleanly. |
| Music correctness | Multi-disc album, compilation, multiple artists, duplicate playlist entries and artist with over ten songs play the intended sequence. |
| Queue trust | 500-track queue survives process death with current position, repeat and shuffle intact; Play Next/reorder/remove behave consistently. |
| Offline commute | Download, terminate app, disable network, cold launch, browse/search, select from phone and car, seek/skip, and reconnect without losing state. |
| Download lifecycle | Suspension, process termination, dropped connection, cancellation and full disk do not lose completed files or silently abandon jobs. |
| Audio quality | FLAC, MP3, AAC/M4A, ALAC, Opus/Ogg and representative transcodes tested where supported; unsupported formats fail clearly or fall back. |
| Continuous playback | Gapless test album; long locked-screen session; calls/navigation prompts; headphone unplug; Bluetooth/AirPlay reconnect. |
| Car experience | Physical Android Auto and CarPlay with locked phone, cold start, offline selection, long catalogs, queue and voice requests. |
| Server integration | Playlist permissions, favorites and playback reporting checked against the server versions advertised as supported; offline reporting has defined semantics. |
| Performance | Measure 10k/50k-track libraries; use existing design targets of 1.5-second LAN playback start and 500-ms search after debounce as goals, not claimed measurements. |
| Accessibility | VoiceOver/TalkBack, large text, landscape, focus order, seek adjustment and labeled queue controls. |
| Distribution | Signed release artifacts, upgrade retention, store metadata/screenshots, support contact, accurate privacy behavior and recovery/source baseline. |

**Decision:** proceed with the reliability work and targeted parity additions. The existing architecture can cover much of the everyday feature set. A claim to be the most capable Jellyfin player should wait for substantially broader functionality and comparative device testing; it is not supported by the current code or this audit.

## Audit baseline

The app source was inspected without implementing the recommended feature changes. Compilation generated normal build outputs. The report and isolated reproductions are the audit deliverables.

SHA-256 of inspected main application sources:

```text
lib/main.dart     46eb8d1942b2c164e72c45ee5bf606754da7bce3c323354d60061da5d201ffd3
lib/app.dart      7221334d892505afb9871bf294960c66889e088ce7bafbe46c1a8ec43d8dd748
lib/jellyfin.dart c69dc2365bc72662941fd5acde279fc74d27ac6ef9ce6e26975dc762eb851d8e
lib/playback.dart 5d783aba2ee5fbfa8a311642aca7ac0fd4c6f77ca27a1bffd986a9e14192f604
```
