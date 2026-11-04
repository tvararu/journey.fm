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
  bar's bottom accessory (`tabViewBottomAccessory(isEnabled:)`, which
  needs iOS 26.1, the app's minimum)
- `NavigationStack` with the system navigation bar, large titles and
  back swipe
- `List` and `LazyVGrid` for shelves and track lists; `.searchable` for
  search; `.fullScreenCover` for now playing, zooming out of the mini
  player (`.navigationTransition(.zoom)`, which also gives the swipe
  down to close); `.contextMenu` and `.swipeActions` for album and
  track actions
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
| Album | title, album artists, year, genres, cover art, date added; from 2 Nov the first release date, RYM rating, label, ReplayGain and every `KEY:Value` tag the journey.fm plugin serves |
| Artist | name, image (album artists only), description |
| Track | title, disc and track number, duration, artists, album; from 2 Nov credits (Jellyfin's people and the `PERFORMER` tags), tags, ReplayGain, lyrics |

Jellyfin's track count per album can be wrong, so counts and total
durations come from the synced tracks.

Not available:

- Genre descriptions and moods: no source has them
- Artist origins: 49 of 293 artists have one, so no flags
- Whether a track is instrumental: not in the tags, so instrumental
  tracks look like tracks without lyrics
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
`mise run ios cli sync [--full] | stats | art | search <words> | play
<words>`, with its database, covers and audio in `apps/ios/build/cli`.
`play` plays the album of the first matching track muted, seeks near the
end of the track and prints the hand-over to the next one.

### Commands

| `mise run ios …` | Does |
|---|---|
| `sim` | Build, install and launch on the booted simulator |
| `device` | Build and install on the paired iPhone (Developer Mode on), without opening it |
| `log` | Stream the app's `fm.journey.app` logs from the simulator |
| `test` | JourneyKit's tests |
| `format` | `swift format` with `apps/ios/.swift-format`, then lint |
| `cli …` | The `journey` command |
| `testflight` | Archive, upload, and wait until App Store Connect has processed the build |

Day to day, changes go to the phone with `device` (Developer Mode is on,
the phone is registered with the team). TestFlight isn't part of the
loop.

Debug builds sign in on their own when launched with `JELLYFIN_URL`,
`JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`, which `sim` passes from
mise; release builds never read them. On the simulator, Orca
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
- Audio: Core Audio decodes FLAC natively, so `AVAudioEngine` with one
  `AVAudioPlayerNode` replaces Dorsal's SFBAudioEngine. Tracks stream
  from `/Audio/{id}/stream?static=true` (the original file) into
  Caches, which keeps the last ten. The decoder is `ExtAudioFile` over
  `AudioFileOpenWithCallbacks`, whose read callback waits for bytes that
  haven't arrived, so playback starts about half a second after Play
  rather than after the 30 to 50 s a whole track takes at the 7 to 12
  Mbit/s measured from sol. A feeder thread keeps five seconds decoded
  ahead and schedules the next track's buffers straight after the
  current one's, which makes playback gapless; a test renders two tracks
  offline and checks the second starts on the sample after the first
  ends. A next track in another format is resampled to the current one.
  A seek far into a track still streaming would make Core Audio scan
  every FLAC frame from the start, at download speed, so the decoder
  reads the SEEKTABLE (`flac` writes a point every 10 s; both files
  checked on 1 Nov had one, and a file without falls back to the scan)
  and opens the file as the header followed by the bytes from the
  nearest point. That first read lands past the download, which
  restarts it with a `Range` request there (Jellyfin answers 206); once
  the end arrives, the gap is fetched before the file is cached. A seek
  to 14 minutes into a 17-minute track plays within a second.
- Downloads: a background `URLSession` (`fm.journey.app.downloads`, four
  connections) into `Application Support/audio`, excluded from backup.
  The `download` table holds what is wanted; a row is saved once the
  file is in place after a 2xx response. The audio's version is the
  container and duration to the tick, so a re-ripped track downloads
  again while a tag rewrite, which keeps both, doesn't. On launch, on
  sync and when the network returns, files and rows are reconciled. The
  system gets at most four tracks you saved and four from Download All
  at a time, and each finished task hands it the next, also when iOS
  wakes the app in the background to deliver results. Handing it all
  7,706 at once (1 Nov) made nsurlsessiond open every request together,
  thousands against Jellyfin, because HTTP/2 doesn't count streams
  against the connection limit. A failed track waits five minutes before
  the next attempt, or until launch, sync or the network returning. A
  track streamed while waiting to be saved is saved from the stream and
  its download cancelled.

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
- No sync status in the title bars: Settings shows the last sync and
  any failure, and offline shows as dimmed tracks that aren't on the
  phone. Failures never block browsing. A 401 signs out with a message
  on the sign-in screen. Pull to refresh runs a delta sync.

Step 3:

- Home: Recently Added (pushes the full list) and twelve Random Albums,
  reshuffled on pull to refresh. `tabBarMinimizeBehavior` is `.never`
  on Home, `.onScrollDown` on Library.
- Library: Albums and Artists as capsule buttons (Downloaded joins them
  as a toggle in step 5), a sort Menu (Title, Artist, Year, Recently
  Added; default Artist, then year within an artist) and a list/grid
  toggle, all kept in `@AppStorage`; no filter field, since Search and
  the index cover finding things. The grid has two columns of covers
  with title and artist below. Lists get an A–Z index from Jellyfin's
  sort names (`#` for digits, decades when sorted by year, none for
  Recently Added), and each letter or decade heads its section, as in
  Apple Music.
- Where title and artist repeat (Celldweller's five End of an Empire),
  the subtitle adds the track count.
- Album page: no title in the bar; cover, title (never truncated),
  artist (pushes the artist), "1982 · Punk" then "13 tracks · 44 min"
  from the synced tracks, Play and Shuffle, tracks (tap plays the album
  from that track). Disc headings only on multi-disc albums; a track's
  artist only when it differs from the album's; More by the artist only
  when there is more.
- Artist page: image, name, "16 albums · 1972–2013", Play and Shuffle
  (every album, oldest first), then every album as a row, oldest first,
  the same for one album or sixteen.
- Search tab: `.searchable` on the Search tab's own stack, its field
  always shown (`.navigationBarDrawer(displayMode: .always)`; otherwise
  it hides under the title once recent searches make the page scroll),
  local FTS5 with word-prefix matching, results grouped Artists, Albums,
  Tracks with a few of each and See All. A track result opens its album
  and plays from it. Recent searches fill the empty state.
  Tapping the tab you're on goes back to its top page; on Search's top
  page it focuses the field.
  Matching ignores hyphen variants (Bong-Ra is tagged with both U+2010
  and an ASCII hyphen).
- Context menus on every album tile and track row: Play, Shuffle, Play
  Next and Add to Queue (tracks: Play Next and Add to Queue, also on the
  row's swipe actions), Download or Remove Download, Go to Album or
  Artist. Now playing's More menu also has Download.
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
  Tapping it opens now playing, which grows out of the bar and shrinks
  back into it, as in Apple Music.
- Now playing follows Apple Music's: a full-screen cover, over the
  status bar, on a dark backdrop of the cover blurred, with a
  grabber-sized handle at the top that shows it swipes down and closes
  it when tapped (VoiceOver: Close). Measured against Music's: the
  cover fills the width less 24 pt while playing and shrinks to 73% of
  that while paused, growing with a bouncy spring (0.5 s, bounce 0.3)
  and shrinking without one. Below it the title and artist with a "…"
  menu (Download, Go to Album and Go to Artist, each naming its
  target); a thin scrubber with no thumb, elapsed and remaining either
  side of a Lossless badge for FLAC, ALAC, WAV and AIFF; previous
  (restarts after 3 s), play/pause and next, which shrink inside a grey
  circle while pressed; the system volume slider (`MPVolumeView`, which
  the simulator doesn't draw); then AirPlay (`AVRoutePickerView`) and
  the queue button, leaving the lyrics slot empty until step 9. Music's
  favourite, share, pin, station, credits, suggest less and playlist
  actions are left out.
- The queue button crossfades the cover for one list and turns white
  while open. The list holds History (the latest 100 tracks played, each
  once, from the play log; Clear hides them without forgetting them;
  tapping one plays it and keeps Up Next), a header row (cover, title,
  "…"), then shuffle and repeat (off, all, one) as capsules and Up Next,
  pinned as a section header. It opens at the header, so History sits
  above it until pulled down, unless the whole queue fits. Reorder
  handles always show: tap an Up Next track to play it, long-press to
  remove it, Clear empties Up Next. Scrubber and controls stay put.
  Music shrinks the cover into the header instead of crossfading, but
  SwiftUI's matched geometry doesn't animate into a `List` row.
- "Played" on a track row means it became the current track earlier in
  this queue, shown as secondary text; starting an album at track 3 does
  not mark tracks 1 and 2. Home gains Recently Played, the first shelf:
  albums with a counted play, newest first.
- A play counts once half the track or 4 minutes has been heard,
  whichever is less, and never for a track under 30 s; seeking adds
  nothing and pausing keeps what was heard. Each one goes in the play
  log on the phone, which Recently Played and History read. Plays from
  before the log were dropped.
- The queue and position are saved on every change, on pause and every
  ten seconds while playing; after a relaunch the mini player shows the
  last track, paused where it stopped. Previous restarts the track after
  three seconds. Repeat One still lets Next move on.

Step 5:

- The album page's toolbar has Download, or Remove Download (confirmed)
  once every track is wanted. Download progress is linear: a bar under
  the album header ("Downloading 3 of 13"), a state per row (saved,
  downloading with a ring, waiting), a badge on covers when an album is
  complete. Settings shows the space downloads take and what is free,
  and Remove All Downloads (confirmed).
- Offline (no network, or the last sync couldn't reach the server),
  tracks not on the phone are dimmed, not hidden or disabled; tapping one
  offers Download When Online. A queue that reaches a missing track
  offline skips it and marks it "Skipped: not on this iPhone". Played
  tracks still in the stream cache count as on the phone.
- Downloads pause while less than 2 GB is free, and resume when space
  returns.

Step 6:

- Seeking past what has downloaded jumps there with an HTTP range
  request; playing starts as soon as the rest of the current track is
  scheduled, without waiting for the next track to open. The scrubber
  also seeks on VoiceOver adjustments, not only at the end of a drag.
- A track being saved by step 5 plays from the stream, not the
  background download, whose bytes stay private until it finishes; when
  the stream completes, its file is saved and the download cancelled.

Step 7:

- Download All shows one progress row in Settings ("1,234 of 7,706
  tracks"), with each pause named: no network, waiting for Wi-Fi (Download
  All never uses cellular or Low Data Mode; tracks you save do), Low
  Power Mode, or out of space (less than 2 GB free). When every track is
  saved, Download New Albums turns on; after each sync it saves the
  albums Jellyfin added since the last one. Remove All Downloads turns
  both off.
- Downloads go one album at a time per request: the journey.fm plugin's
  `GET /Journey/Archive?ids=…` streams the tracks as one uncompressed tar
  (at most 50 per request), which the app unpacks as it lands. Four
  albums are in flight per class, all in the background session. An
  interrupted album resumes from where it stopped, through the
  endpoint's range support and the failed task's resume data.

Steps 8 and 9 (2 Nov), designed in
`docs/superpowers/specs/2026-11-02-ios-metadata-lyrics-design.md`:

- Album page: the meta line puts a release type that isn't Album first
  ("EP · 2012 · Stoner") and opens the album's genre, or a menu of its
  genres. After the tracks: Details (released, this edition when it
  differs, label, catalogue number, format, country, language, barcode,
  RYM genres, scene, descriptors), Credits (each person once, roles and
  track numbers, "all tracks" where it applies) and Ratings (RYM score
  and votes, opening the RYM page; rank; when it was fetched). Rows and
  sections without values are left out.
- View Credits on every track's context menu and in now playing's "…"
  menu opens a sheet: Performers, Written By, Production and Engineering,
  then the ISRC.
- Library gains a Genres capsule (the curated `GENRE` tag, 134 genres)
  with an A–Z index; a genre page lists its albums by artist, with Play,
  Shuffle and the grid or list layout.
- Artist pages show TheAudioDB's description, three lines then More.
- Search also finds credited people (the album, "Madlib · producer,
  engineer") and lyric lines (the track, with the line).
- Lyrics (the quote button left of AirPlay, greyed out without lyrics)
  replace the art in now playing as the queue does. Synced lines follow
  playback with the current one brightest, played ones dimmest; tapping
  a line seeks; scrolling by hand pauses the following for 3 s. Plain
  lyrics scroll freely under "Not Synced". The choice stays across
  tracks.
- Every track's lyrics are kept on the phone: after each sync they are
  fetched 8 at a time beside the covers (Settings shows "Fetching
  lyrics"), again when a track's `Etag` changes; a 404 is remembered as
  no lyrics. All 5,551 take about 10 MB.
- Playback runs at the album's ReplayGain, or the track's without one,
  capped by the peak so nothing clips; there is no setting. Jellyfin's
  own `NormalizationGain` is its own scan and is ignored.

Left for the catalogue: Celldweller's five albums want distinct titles,
and the hyphen variants want one spelling, both written back to the tags
rather than patched on the phone.

## Snagging (1 Nov)

A pass through every screen on the simulator after step 7, by
screenshot and accessibility tree. Every control on Home, Library,
album, now playing, queue, Search and Settings has an accessibility
label.

Fixed:

- Play on album and artist pages had no icon: `.glassProminent` dropped
  it until the label style was set to title and icon.
- A downloading row spun forever: iOS draws a circular `ProgressView` as
  a spinner whatever its value, so the ring is two circles, one trimmed.
- Settings said "0 tracks · Zero kB" with nothing downloaded; now "None".
  Track counts in the thousands now have separators ("7,706 tracks").
- The scrubber only sought at the end of a drag, so VoiceOver's adjust
  never moved playback; a change outside a drag now seeks.
- Now playing left a band of empty space under its controls and had a
  tiny More button; the shuffle, repeat, AirPlay and queue row now sits
  at the bottom and More is full size.
- See All lists drew a stray separator above the first row.
- The badge on downloaded covers was a small dark arrow, invisible on
  dark art; it is now the tint with a white arrow, scaled to the cover.
- Two downloads calls overlapping (a sync and the network returning)
  spun the main actor forever; found by a test hanging.

Open:

- The Search title is inline over recent searches and large over
  results, apparently the navigation bar's own handling of an
  always-shown search field; left as it is.
- Not checked on hardware: the lock screen and Control Center, call and
  Siri interruptions, unplugging headphones, AirPlay, and the background
  launch that queues the next downloads while the app is closed.

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
4. **Play.** Done 1 Nov: gapless `AVAudioEngine` playback streamed from
   Jellyfin, lock screen and remote controls, interruptions and route
   changes, the mini player, now playing and queue sheets, Play, Shuffle,
   Play Next and Add to Queue, Recently Played, resume where playback
   stopped.
5. **Save offline.** Done 1 Nov: Download and Remove Download on
   albums and tracks through a background `URLSession` into Application
   Support, checking the HTTP status; download states on album pages,
   rows and covers; offline dimming and skipping; storage and Remove All
   Downloads in Settings; re-download when a track's audio changes.
6. **Seek while streaming.** Done 1 Nov: range requests for a seek past
   the downloaded part, starting the decoder at the nearest FLAC seek
   point; a track that step 5 is still saving plays from the stream.
7. **Download everything.** Done 1 Nov: Download All and Download New
   Albums, in the system's background session. On 3 Nov downloads stalled
   at 4 tracks every 15 to 20 minutes with the app suspended: a transfer
   queued from the background starts only at iOS's discretion, after a
   delay that grows with every wake. Queuing 500 tracks instead split
   sol's upload 500 ways over one HTTP/2 connection, and a
   `BGContinuedProcessingTask` was expired within minutes, as Apple
   reserves it for short jobs a tap starts. Apple's advice for thousands
   of transfers is fewer, larger ones, so since 4 Nov each request is an
   album, about 400 MB instead of 45, and each wake refills 4 albums.
8. **Metadata.** Done 2 Nov, from the journey.fm Jellyfin plugin:
   details, credits and ratings on album pages, a credits sheet per
   track, browsable genres, artist descriptions, search by credit, and
   ReplayGain in playback. Genre descriptions, moods and artist origins
   have no source yet.
9. **Lyrics.** Done 2 Nov: every track's lyrics on the phone, synced
   lyrics that follow playback and plain ones, in the slot left of
   AirPlay, and search by lyric line.
10. **Play log.** Done 2 Nov: a play counts after half the track or 4
    minutes heard (never under 30 s), is kept on the phone and feeds the
    queue's History and Recently Played.
