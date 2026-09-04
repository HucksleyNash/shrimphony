# Shrimphony reliability implementation and acceptance

September 4, 2026 · development version 1.0.0+1

The eight code reliability findings in `LAUNCH_AUDIT_2026-09-04.md` have been addressed. Distribution finding 9 is partially complete and remains a release gate. This report distinguishes executable verification from hardware and publisher prerequisites; it does not claim that every launch acceptance item has passed.

Scope: the audit’s nine concrete release findings and completed app workflows. The later competitive roadmap (lyrics, EQ, normalization, casting, Siri, additional backends, and similar new features) is not implemented by this reliability release.

## Findings and disposition

| Audit finding | Implementation | Evidence / remaining requirement |
|---|---|---|
| 1. Album/disc order | Preserve server order for one collection; apply full sort keys when merging libraries. | Original regression now passes; overlapping-library deduplication and multi-disc ordering tested; real-server album order checked. |
| 2. Incomplete artist actions | Shared collection query supplies every artist song to phone and car actions. | Device UI Play/Download All includes all 12 fixture songs. Real-server artist query checked. |
| 3. Truncated restoration | Persist every logical queue entry and explicit play order; restore index, position, shuffle and repeat. Fix native idle loading so Resume retains position. | A 500-entry queue at index 250/9 seconds survives separate app processes on Android and iOS; offline phone/car playback succeeds with the original fixture server stopped. |
| 4. Offline inconsistencies | Durable artwork and collection metadata, local album/artist/playlist browsing and search, cold launch from downloads, car routes resolve local data before HTTP. | Both device suites prove offline search and car selection with zero metadata/audio HTTP requests. Duplicate playlist entries remain intact in local snapshots. |
| 5. Shuffle/queue disagreement | A single materialized queue order; serialized edits; Play Next is the next visible/heard entry. | Real native players verify shuffled insertion, skip, reorder, remove and complete restoration on both platforms. |
| 6. iOS artwork | Android content provider stays Android-only; Apple metadata receives authenticated artwork URLs or durable local files; native CarPlay loads thumbnails. | Platform metadata contracts and native compilation pass. Lock-screen/CarPlay artwork still needs visual physical-device acceptance. |
| 7. Recovery | Durable pending/failed jobs, progress, pause/resume/retry/cancel, Wi-Fi policy, storage limit and bulk removal. Retry/Skip UI; queue-save failure is surfaced. | Controlled interruption, failed retry, cancellation, paused restart, Wi-Fi and capacity checks pass. Native playback failure preserves its queue and UI Retry recovers. Jobs restart on reopening; no claim of OS-scheduled transfer after termination. Actual full-disk and physical suspension tests remain. |
| 8. Scaling | Publish cached/initial data while remaining pages load; phone and car share progressive library shuffle. | Synthetic 50,000-song catalog keeps every song; first page 15 ms, complete refresh/cache 858 ms on this Mac. Native queue restoration measured at 500 entries; these catalog timings are not a 50k phone-render/native-player benchmark. |
| 9. Distribution/support | App Git baseline, signing guard, signing template, About/privacy/licenses/diagnostics, scoped account cleanup, release notes, website support/privacy/availability corrections. | Missing private production signing, approved CarPlay distribution profile, public contact and install URLs. Website builds locally; saved Sites project returns `project_not_found` through the available connection. |

Additional defects found during execution: the artist listing endpoint omitted many server artists; native queue loading reset resumed playback to zero; compact landscape overflowed with large text; extensionless HLS failed native source detection; iOS transport-security keys conflicted and blocked private HTTP media; 32-bit FLAC failed iOS native decoding; car category rows exposed invalid collection actions. These paths were corrected and covered by regression/device checks.

## Test environment and evidence

Flutter 3.44.2 / Dart 3.12.2; Android Pixel 9/API 35 emulator (`emulator-5554`); iPhone 17 Pro/iOS 26.5 simulator. The user’s private Jellyfin 10.11.11 server contains 9,298 songs, 1,242 albums and 714 artists. Credentials are absent from source and this report. Normal production-entry builds were rebuilt without live-test session defines; both artifacts were scanned for the private test token. The temporary test session was logged out and its private configuration files removed. Real-server test playlists were deleted and the tested favorite restored.

The original app baseline is Git commit `a3621fd`; reliability changes are saved on `codex/reliability-release`. The independently versioned website remains in its existing worktree. Local execution logs are under ignored `audit/results/`. The compile-only Android artifact is `build/app/outputs/flutter-apk/app-release.apk`; the iOS simulator artifact is `build/ios/iphonesimulator/Runner.app`. Neither is a signed store distribution. Reproduction commands are in `README.md`; the original launch regression checks are now included in the default suite.

| Completed feature / check | Evidence |
|---|---|
| Static analysis and unit contracts | Final static analysis: no issues. Default suite: all 26 tests pass, including original audit reproductions and 50k catalog. Android production APK compiles with explicit unsigned mode; ordinary release builds correctly refuse missing signing. iOS simulator production-entry compilation passes. |
| Sign-in and navigation | Both device UIs test empty input, rejected password, successful sign-in, library navigation and unavailable-server access to downloads. URL contracts cover public HTTPS, private HTTP, IPv6, tailnet addresses and reverse-proxy subpaths. Actual public HTTPS/proxy deployment and TLS failures were not provisioned. |
| Library, artist, genres, search | Live API catalog/artist/genre queries, grouped search and native library workflows; offline search uses local metadata. The online search’s existing 60-result limit remains a later roadmap item. |
| Player and queue | Native play/pause/seek/previous/next; 500 entries; shuffled Play Next/reorder/remove/clear; repeat and position persistence; separate-process offline restoration. |
| Full library / long car catalogs | Additional native check covers progressive shuffle of 1,000 unique songs and browsing every artist song through car pagination. |
| Favorites and playlists | Live favorite on/off with restoration; temporary playlist create/rename/add/reorder/remove and cleanup. Jellyfin 10.11.11 deduplicates repeated insertions itself; local/client duplicate preservation is tested separately. Non-owner/read-only playlist permissions still require a restricted server account. |
| Server playback reporting | Live Jellyfin sessions reflect the selected song, paused state and exact reported position; native skip sends the previous song’s stop position. Offline reports are best effort, without replay. |
| Instant Mix and devices | Live Instant Mix and controllable-session discovery pass. No remote receiver was commanded without identifying a dedicated test destination; one-way handoff still needs receiver acceptance. |
| Direct / transcoded audio | MP3, AAC, M4A/AAC, ALAC, WAV, FLAC 16/24/32-bit, Ogg/Vorbis and Opus use generated samples. iOS routes Ogg, Opus and 32-bit FLAC through AAC fallback; supported originals remain direct. Streaming and downloaded playback are checked. |
| Real server audio | Android and iOS pass original FLAC and AAC HLS at 320/96 kbps with seeks; downloaded FLAC plays. Observed playback start approximately 0.4–1.1 seconds; full library refresh approximately 17–19 seconds, with one 30-second outlier under concurrent work. These are tailnet measurements, not a LAN guarantee. |
| Automatic transitions | Adjacent generated FLAC tracks advance without manual skip. This checks continuity, not waveform-perfect gaplessness; direct/transcoded/downloaded gapless albums still need listening/capture on hardware. |
| Download lifecycle/storage | Durable manifest/artwork, preserved completed files, interrupted response, retry/cancel, paused restart, capacity rejection, Wi-Fi wait/resume, account-scoped cleanup. Simulated capacity is not a physical full-disk test. |
| Android background session | Real app stays playing behind Home; system media Pause/Play/Next update native state and advance the selected song. Physical lock, headset unplug, calls, navigation ducking and output reconnection remain. |
| Android Auto | Shared browse/search/play contracts and native service wiring checked. Installed emulator package is `1.2.542030-stub`; settings redirects to Play Store. DHU is installed, but the full Android Auto app/head-unit server is not available in that emulator. |
| CarPlay | Native scene/bridge compiles; simulator display can be enabled and shows Shrimphony. Browse/play contracts pass through the shared Dart handler. Native template interaction and physical locked-phone acceptance are not marked passed. |
| Appearance/accessibility | Both device suites check portrait/landscape at large text, dark theme, overflow exceptions and labeled navigation controls. Full VoiceOver/TalkBack focus order and screen-reader seek operation remain manual acceptance. |
| Privacy/support/data removal | UI privacy, licenses and diagnostics exercised. Account deletion removes only its downloads/cache/jobs/preferences/playback and leaves another account’s data. Public support destination still needs configuration. |
| Website | Existing design and independent repository retained; local home/privacy/support routes respond, lint and production build pass. Public deployment is blocked by project access and missing publisher details. |

## Remaining launch gates

1. Supply a public support URL/email and actual TestFlight/Play beta or store URLs. Configure `SUPPORT_URL` in release builds; replace the truthful pre-release availability text with those destinations.
2. Configure and back up the Android release key, supply Apple distribution credentials/profile, and verify the granted CarPlay entitlement in a built archive. Review dependency privacy manifests, archive contents, upgrade retention and store metadata. The iOS HTTP exception needs the private/self-hosted server justification during review.
3. Install/enable the full Android Auto app on the test phone/emulator and connect DHU. Complete CarPlay native UI plus both physical vehicle workflows with a locked phone and offline cold start.
4. Complete hardware-only audio route, interruption, prolonged background, true gapless, full-disk, and screen-reader acceptance. Provide a dedicated remote playback receiver and restricted Jellyfin account for those integration checks.
5. Restore access to the existing Sites project before publishing website changes. No replacement site was created and no public deployment was claimed.

The app is substantially better tested and has a recoverable source baseline, but these gates prevent calling it a fully accepted public release.
