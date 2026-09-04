# Shrimphony Design System

## Product Direction

A native iOS and Android music player for a user's own Jellyfin server. It should
feel immediately familiar to Spotify users without copying Spotify's branding or
screen designs. The core promise is: connect once, find any song quickly, and
start or resume playback in one or two taps.

### Product principles

1. Playback is always the primary action.
2. The same queue powers the phone, lock screen, headset, CarPlay, and Android Auto.
3. Preserve useful content while refreshing; avoid blank screens and blocking spinners.
4. Use native platform behavior when it is safer or more accessible than custom UI.
5. Do not invent recommendations the Jellyfin data cannot support.

## Information Architecture

```text
First launch
└── Server URL → credentials → music-library selection

App shell
├── Home
├── Search
├── Library
└── Persistent mini-player
    └── Now Playing
        └── Queue

Secondary screens
├── Artist
├── Album
├── Playlist
├── Genre
└── Settings
```

Use three bottom tabs: Home, Search, and Library. Show the mini-player directly
above the tab bar whenever a queue exists. Preserve each tab's navigation and
scroll position when switching tabs.

## Visual System

### Color

Support system light and dark appearance. Dark is the signature presentation,
but it must not be the only usable mode.

| Token | Dark | Light | Use |
|---|---|---|---|
| `background` | `#071A33` | `#FFF7EA` | App background |
| `surface` | `#0E2949` | `#FFFCF6` | Cards, rows, sheets |
| `surfaceRaised` | `#17395F` | `#F4E8D6` | Menus, elevated controls |
| `textPrimary` | `#FFF7EA` | `#071A33` | Primary text |
| `textSecondary` | `#BECBDA` | `#526176` | Metadata and labels |
| `accent` | `#FF594C` | `#FF594C` | Active controls and CTAs |
| `error` | `#FF6B6B` | `#B42318` | Failures and destructive actions |

Artwork may create a subtle sampled-color wash behind Now Playing, but text and
controls always use fixed contrast-safe tokens. Never use color alone to show state.

### Type, spacing, and shape

- Typography: SF Pro on iOS; Roboto on Android. Use native Dynamic Type/font scaling.
- Type roles: title 28/34 semibold; section 20/25 semibold; body 16/22; metadata
  14/19; caption 12/16. These are reference sizes, not fixed accessibility caps.
- Spacing scale: 4, 8, 12, 16, 24, 32.
- Page gutter: 16 phone, 24 tablet. Major sections are 24 apart.
- Radius: 8 artwork/cards, 12 sheets/dialogs, full radius only for filter chips.
- Icon sizes: 20 inline, 24 standard, 32 primary playback.
- Song rows: minimum 64 high. Mini-player: 64 plus safe-area handling.
- Album, artist, and playlist artwork is square; use a two-column phone grid.
- Motion: 160 ms control feedback, 240 ms screen/sheet transitions. No decorative
  autoplay motion. Respect Reduce Motion.

## Screen Contracts

| Screen | Required content | Primary actions |
|---|---|---|
| Server setup | URL, reachability, connection security, credentials | Connect, sign in, retry, cancel back to the active session |
| Home | Recently played, recently added, favorites, random albums; Shuffle All in the app bar menu | Play item, shuffle library |
| Search | Search field; grouped Songs, Albums, Artists, Playlists results | Play song, open entity, see all |
| Library | Playlists, Artists, Albums, Songs, Genres filters; A–Z/recent sort | Browse, play, shuffle |
| Artist | Artwork, name, favorite, top songs, albums | Play, shuffle, open album |
| Album/Playlist | Artwork, metadata, Play, Shuffle, track list | Play collection/track, queue item |
| Now Playing | Artwork, title/artist, progress, transport, favorite, queue | Seek, pause, skip, shuffle, repeat |
| Queue | Current item, manually queued items, remaining context | Reorder, remove, clear, play item |
| Settings | Server/account, libraries, streaming quality, diagnostics | Reconnect, change setting, logout |

Every entity row has a visible trailing context menu. Long press may open the same
menu but is never the only route. Keep song lists as rows, not cards.

## Playback and Queue Behavior

- Tapping Play on a collection replaces the queue and begins with its first track.
- Tapping a track within an album or playlist replaces the queue with that context,
  begins at the selected track, and queues the following tracks.
- Tapping a standalone search result plays that song without synthetic recommendations.
- Play Next inserts immediately after the current track. Add to End appends.
- Collection Shuffle materializes one random order and starts it immediately.
- Toggling shuffle during playback keeps the current track and manual queue order,
  then reshuffles only the unplayed context.
- Repeat cycles Off → All → One with visible state, accessible label, and haptic feedback.
- Persist the queue, shuffle order, repeat mode, current item, and position across restart.
- Never autoplay on launch. Resume only after an explicit action or interrupted-session command.

## Player Surfaces

### Mini-player

Show artwork, one-line title/artist, play/pause, and a thin progress indicator.
Tapping the body expands Now Playing. Play/pause remains independently tappable.

### Now Playing

Order content as artwork, title/artist, seek bar with elapsed/duration, then:

```text
Shuffle   Previous   Play/Pause   Next   Repeat
Favorite                              Queue
```

Swipe down may collapse the player, but always provide a visible collapse button.
Show buffering inside the play control without hiding the existing metadata.

## Search Behavior

- Focus the field when the user deliberately taps it, not every time the tab appears.
- Debounce server search by 250 ms and cancel superseded requests.
- Search titles, artists, albums, playlists, and genres.
- Present grouped top results, followed by See All routes for each entity type.
- Keep old results visible with an inline refresh state until new results arrive.
- A result row shows artwork, title, entity/artist metadata, and its context menu.

## Loading, Empty, Error, and Offline States

- Show skeletons only when loading exceeds about 250 ms. Match final content geometry.
- Load artwork progressively with a neutral music-note placeholder. Image failure
  never blocks text or playback.
- Empty states name the reason and a useful action, such as “No favorite albums yet”
  plus “Browse albums.”
- If the server is unavailable and metadata is cached, retain browsable content and
  show a persistent Server unavailable banner with Retry.
- With no cache, show a full-screen connection state with server address, Retry, and
  Change server.
- During buffering, keep artwork and controls visible, retry automatically, then
  offer Retry and Skip.
- On expired credentials, stop new requests, preserve queue state, and route to sign-in.
- Downloads use the original file when its format is portable and server-transcoded
  AAC otherwise. Only completed files receive the explicit offline indicator.
- Downloaded metadata is scoped per server and user; partial files never enter the
  offline library.

## CarPlay and Android Auto

Car surfaces use system-rendered, driver-safe templates. Do not reproduce the phone UI.
Initial connection and authentication happen on the phone before driving. Playback and
browsing must work while the phone is locked.

```text
Listen Now
├── Resume
├── Recently Played
├── Favorites
└── Shuffle All

Library
├── Playlists
├── Artists
├── Albums
└── Genres
```

- Keep common tasks within three steps.
- Use the system Now Playing surface with artwork, metadata, transport, shuffle,
  repeat, and Up Next where supported.
- Support voice requests for song, artist, album, playlist, genre, Shuffle My Library,
  resume, pause, and next. An empty “play music” request resumes recent playback.
- CarPlay uses Apple CarPlay list/tab/Now Playing templates and the audio entitlement.
- Android Auto production v1 uses `MediaLibraryService`/`MediaSession`; do not depend
  on the beta custom media templates for production distribution.
- Connection errors state what happened and defer phone-only repair until parked.

## Accessibility

- Minimum target size: 44×44 pt on iOS and 48×48 dp on Android.
- Support large text without clipping transport controls or hiding primary actions.
- Label and announce shuffle, repeat, favorite, buffering, progress, and queue position.
- Make progress an adjustable control with elapsed and remaining-time announcements.
- Meet WCAG AA contrast and preserve a logical VoiceOver/TalkBack focus order.
- Announce updated search results without moving focus unexpectedly.
- Respect Reduce Motion, increased contrast, bold text, and platform haptic settings.
- Avoid gesture-only actions, marquee text, and unexpected audio.

## V1 Acceptance Bar

- A returning user resumes music within two taps.
- Search results appear within 500 ms on a healthy LAN after debounce.
- Playback starts within 1.5 seconds on a healthy local server.
- Queue and position survive backgrounding, process death, reconnect, and car handoff.
- Every screen has intentional loading, empty, error, and offline behavior.
- Core flows pass VoiceOver and TalkBack with no unlabeled controls.
- Car browse, voice search, transport controls, and locked-phone playback pass on hardware.

## V1 Non-goals

Do not build lyrics, podcasts/video, social or collaborative features, algorithmic
recommendations, a dedicated Google Cast receiver, EQ, crossfade, themes, widgets,
Watch/Wear apps, or Android Automotive. Playlist editing covers create, rename, add,
remove, and drag-to-reorder.
