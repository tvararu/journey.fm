# iOS app

The player for the library, in `apps/ios`. `docs/library.md` has the end
state and the player design (28 Oct); `docs/dorsal.md` has the prior art
from Dorsal, and `docs/ios-prior-art/` the research into other music
apps (1 Nov).

## UX (1 Nov)

As simple as it can be. Take Spotify's structure, which looks a bit
better than Apple Music's, and build it entirely from stock iOS parts:

- `TabView` for the tabs: Home, Library, then Search as a trailing
  `Tab(role: .search)`, as in Apple Music. The mini player is the tab
  bar's bottom accessory (`tabViewBottomAccessory`, iOS 26)
- `NavigationStack` with the system navigation bar, large titles and
  back swipe
- `List` and `LazyVGrid` for shelves and track lists; `.searchable` for
  search; `.sheet` for now playing; `.contextMenu` and `.swipeActions`
  for album and track actions
- System fonts, colours, symbols, light and dark mode; no custom
  gestures, drawers, tab bars or animations

Almost nothing custom. Where Spotify's look needs custom drawing, the
stock component wins, so the result will look closer to Apple Music
than Spotify in detail. Every tappable element gets an
`.accessibilityIdentifier`, so `orca emulator ax` can drive and check it;
decorative images are hidden from VoiceOver.

No CarPlay: the car is a Tesla.

The app icon is a placeholder: SF Symbols' `music.note`, which Apple's
licence does not allow in app icons. Replace it before anything goes
beyond internal TestFlight.

## What the screens can show (1 Nov)

The phone's database (`JourneyKit/Sources/JourneyKit/Library`) holds
what sync takes from Jellyfin, and nothing else:

| Item | Fields |
|---|---|
| Album | title, album artists, year, genres, cover art, date added |
| Artist | name, image (album artists only) |
| Track | title, disc and track number, duration, artists, album |

Jellyfin's track count per album can be wrong, so counts and total
durations come from the synced tracks.

Not available yet, so any screen that needs it waits for a later step:

- Play history, so no recently played or jump back in: step 4
- Downloaded state and storage used: step 5
- Lyrics: step 8
- RYM, MusicBrainz, Discogs and RED data (ratings, descriptors, labels,
  credits, release types): only in the catalogue (`apps/web`) until tags
  are written back to the FLACs, step 8
- Playlists and favourites: in Jellyfin, but not synced

The library is about 680 albums by 300 album artists. 181 artists have
one album and 48 have two, while a few have ten or more (up to 16), so
artist pages must look right with a single album.

## Structure and dependencies (1 Nov)

Everything but the screens lives in `apps/ios/JourneyKit`, a local Swift
package: the Jellyfin client, the library database and sync, the art
cache and the Keychain session. The app target holds only
`AppModel.swift` and `Views/`. The package also builds `journey`, a
command for testing against the real server without the simulator:
`mise run ios cli sync [--full] | stats | art | search <words>`, with its
database and covers in `apps/ios/build/cli`.

### Commands

| `mise run ios …` | Does |
|---|---|
| `sim` | Build, install and launch on the booted simulator |
| `device` | Build, install and launch on the paired iPhone (Developer Mode on) |
| `log` | Stream the app's `fm.journey.app` logs from the simulator |
| `test` | JourneyKit's tests |
| `format` | `swift format` with `apps/ios/.swift-format`, then lint |
| `cli …` | The `journey` command |
| `testflight` | Archive, upload, and wait until App Store Connect has processed the build |

Day to day, changes go to the phone with `device` (Developer Mode is on,
the phone is registered with the team). TestFlight isn't part of the
loop.

Debug builds sign in on their own when launched with `JELLYFIN_URL`,
`JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`, which `sim` and `device`
pass from mise; release builds never read them. On the simulator, Orca
drives input and reads the screen (`orca emulator tap`, `type`,
`gesture`, `ax`); installing, launching, the keychain, logs and
screenshots go through `xcrun simctl`, which Orca doesn't wrap for iOS.
Never run `orca emulator kill` or `shutdown`: the helper is shared with
deity's simulator pane, which goes dark when it stops. The simulator
runs in dark mode (`xcrun simctl ui booted appearance dark`).

The Jellyfin device ID lives in the Keychain apart from the session, so
signing out and back in, or reinstalling, doesn't add a new device to
Jellyfin's dashboard. The build number is the UTC time of the upload;
`MARKETING_VERSION` in `project.yml` changes only at milestones.

Vanilla Swift and Apple frameworks, plus a package only when it does
something specific that would be annoying to do ourselves:

- Jellyfin: `URLSession` and `Codable`, no SDK
- Database: GRDB 7 over SQLite, for migrations, batch writes, FTS5 for
  search and `ValueObservation`, which keeps the screens current
- Audio: Core Audio decodes FLAC natively (`AVAudioFile` opened a FLAC
  made with `afconvert` on 1 Nov), so `AVAudioEngine` with an
  `AVAudioPlayerNode` scheduling tracks back to back replaces Dorsal's
  SFBAudioEngine. It stays the fallback if play-while-downloading
  (step 6) proves annoying with the system APIs

Sync pages through `/Items` 1,000 at a time with
`EnableTotalRecordCount=false`: Jellyfin takes about 13 s to count 1,000
tracks and 1 s without the count. A full sync of 678 albums and 7,706
tracks takes about 20 s; it runs on first sign-in and then once a day,
and is the only way deletions are noticed. Between full syncs, a delta
asks for items with `MinDateLastSaved` an hour before the last sync. A
track whose album isn't stored yet waits for the next sync.

## Screens (1 Nov)

Artboards for every step, drawn by Claude Design from the docs above,
are in `data/design/ios-board.zip` (gitignored; backed up to sol with
`mise run push`). Each artboard names the SwiftUI component for every
element; `renders/` has the PNGs, `renders/Main.png` the flow and
`renders/o-decisions.png` the decisions. What follows is what was agreed
from it.

Navigation:

- Launch goes to Sign in without a session, then First sync, then the
  tabs. First sync is its own screen, showing phases with running
  counts rather than a percentage.
- Home's toolbar has only a gear, which opens Settings as a sheet:
  account, library counts, last sync, Sync Now, Sign Out, storage and
  downloads later. Library's toolbar holds sort and layout.
- Sync status is the `navigationSubtitle` on Home and Library: "Synced
  5 min ago", "Syncing…", "Couldn't sync · Synced yesterday",
  "Offline · Synced 3 h ago". Failures never block browsing; the detail
  is in Settings. A 401 signs out with a message on the sign-in screen.
  Pull to refresh runs a delta sync.

Step 3:

- Home: Recently Added (pushes the full list) and twelve Random Albums,
  reshuffled on pull to refresh. `tabBarMinimizeBehavior` is `.never`
  on Home, `.onScrollDown` on Library.
- Library: Albums and Artists as capsule buttons (Downloaded joins them
  as a toggle in step 5), a sort Menu (Title, Artist, Year, Recently
  Added; default Artist, then year within an artist), a list/grid
  toggle and a `.searchable` filter for this screen only, all kept in
  `@AppStorage`. The grid has two columns of covers with title and
  artist below. Lists get an A–Z index from Jellyfin's sort names (`#`
  for digits, decades when sorted by year, none for Recently Added).
- Where title and artist repeat (Celldweller's five End of an Empire),
  the subtitle adds the track count.
- Album page: no title in the bar; cover, title (never truncated),
  artist (pushes the artist), "1982 · Punk" then "13 tracks · 44 min"
  from the synced tracks, Play and Shuffle (from step 4), tracks. Disc
  headings only on multi-disc albums; a track's artist only when it
  differs from the album's; More by the artist only when there is more.
- Artist page: image, name, "16 albums · 1972–2013", Play and Shuffle
  (from step 4), then every album as a row, oldest first, the same for
  one album or sixteen.
- Search tab: `.searchable` on the Search tab's own stack, local FTS5
  with word-prefix matching, results grouped Artists, Albums, Tracks
  with a few of each and See All. A track result opens its album (and
  plays from it in step 4). Recent searches fill the empty state.
  Matching ignores hyphen variants (Bong-Ra is tagged with both U+2010
  and an ASCII hyphen).
- Context menus on every album tile and track row: Go to Artist now;
  Play, Shuffle, Play Next and Add to Queue in step 4; Download or
  Remove Download in step 5.
- Artists with no albums are hidden: Jellyfin returns five empty
  duplicates (Septicflesh, Various Artists and others), leaving 295.
- Covers are fetched into Application Support after each sync, four at
  a time, so browsing offline shows art; Caches can be purged by iOS.
  All 932 album and artist covers at 600 px take 83 MB and about two
  minutes on first sync.
- Jellyfin data the phone works around: an album artist listed twice on
  one album (Bong-Ra's two hyphens resolve to one ID) is stored once,
  and nine albums arrive with no album artist IDs at all (Down, Septic
  Flesh, Trouble, Run the Jewels, The Desert Sessions), so they have no
  artist page until their tags are fixed.

Step 4:

- Mini player: `tabViewBottomAccessory(isEnabled:)`, hidden until
  something is queued. Expanded: art, title, artist, play/pause, next.
  Inline (`tabViewBottomAccessoryPlacement`): art, title, play/pause.
  Tapping it opens now playing.
- Now playing: a full-height sheet with art, title, "artist · album",
  scrubber with elapsed and remaining, previous (restarts after 3 s),
  play/pause, next, shuffle, repeat (off, all, one), AirPlay
  (`AVRoutePickerView`, the one UIKit wrapper) and the queue. A More
  menu goes to the album or artist. No volume slider.
- Queue: a second sheet with medium and large detents; now playing
  fixed at the top, Up Next below with Play Next items marked; swipe to
  remove, Edit to reorder, Clear empties Up Next.
- "Played" on a track row means already played in the current queue,
  shown as secondary text. Home gains Recently Played.

Steps 5 to 8:

- Download progress is linear: a bar under the album header, a state
  per row (saved, downloading, waiting), a badge on covers when an album
  is complete. Settings shows storage and Remove All Downloads.
- Offline, tracks not on the phone are dimmed, not hidden or disabled;
  tapping one offers Download When Online. A queue that reaches a
  missing track offline skips it and marks it.
- Seeking past what has downloaded uses an HTTP range request.
- Download All shows one progress row in Settings, with each pause
  named (Low Power Mode, waiting for Wi-Fi, storage full). When it
  finishes, Download New Albums turns on.
- Lyrics replace the art in now playing; the current line is bold,
  tapping a line seeks. Step 8 metadata appears only where it exists.

Left for the catalogue: Celldweller's five albums want distinct titles,
and the hyphen variants want one spelling, both written back to the tags
rather than patched on the phone.

## Roadmap

1. **Ship to the phone.** Done 1 Nov: builds go to TestFlight with
   `mise run ios testflight`.
2. **Sign in and sync.** Done 1 Nov: sign-in to sol's Jellyfin
   (`JELLYFIN_URL`, https://jellyfin.example; the account is
   in `JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`), the session in the
   Keychain, full and delta sync into the local database, album art
   cached by `ImageTags`. A stand-in screen shows the counts and the
   albums added most recently.
3. **Browse and search offline.** Done 1 Nov: the three tabs, album
   and artist pages, search against the local database only, covers
   kept on the phone; as in Screens above.
4. **Play.** `AVAudioEngine` with gapless playback, lock screen and
   remote controls, interruptions and route changes, the mini player
   and now playing sheet, resume where playback stopped.
5. **Save offline.** Save tracks or albums through a background
   `URLSession` into Application Support, checking the HTTP status;
   played tracks stay cached; re-download when an item's audio changes.
6. **Play while downloading.** Decode a file that is still being
   written, with the system APIs, or SFBAudioEngine if they fight it.
7. **Download everything.** Hand every task to the system up front so
   it carries on with the phone locked and the app killed.
8. **Lyrics and metadata.** Synced lyrics from `/Audio/{id}/Lyrics`,
   genres and the rest once tags are written back to the FLACs.
