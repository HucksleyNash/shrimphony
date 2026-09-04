# Reliability release — 1.0.0+1 development

- Preserve album/disc ordering and use the complete artist collection for Play, Shuffle, and Download All.
- Keep one visible play order. Play Next remains next under shuffle; restore the complete queue, selected song, position, shuffle, and repeat after restarting.
- Browse and search downloaded songs, albums, artists, and cached playlists offline, including car selection and durable artwork.
- Persist pending and failed download jobs; add progress, retry, cancel, pause, Wi-Fi policy, storage limits, and bulk removal. Interrupted jobs resume when the app reopens.
- Show playback failures with Retry/Skip and report queue-save failures. Use explicit direct-file/HLS sources for native decoding and transcoded seeking.
- Publish initial library results before the complete scan and share library shuffle between phone and car.
- Add car Downloads/Playlists, paginated catalogs, platform-correct artwork, and CarPlay error recovery.
- Add About, privacy, licenses, diagnostics, and complete account data removal. Fix compact landscape layouts with large text.
- Require a private Android release signing configuration; remove debug signing from release builds.

Not a public release: production signing, approved CarPlay distribution entitlement, public installation/support destinations, and physical-device acceptance remain required. No casting, lyrics, EQ, normalization, or other later competitive-roadmap feature is claimed by this release.
