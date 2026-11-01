# iOS app

The player for the library, in `apps/ios`. `docs/library.md` has the end
state and the player design (28 Oct); `docs/dorsal.md` has the prior art.

## UX (1 Nov)

As simple as it can be. Take Spotify's structure, which looks a bit
better than Apple Music's, and build it entirely from stock iOS parts:

- `TabView` for the tabs (Home, Search, Library), with the mini player
  as the tab bar's bottom accessory (`tabViewBottomAccessory`, iOS 26)
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

The library is about 680 albums by 300 album artists, mostly one album
per artist, so artist pages are often a single album.

## Structure and dependencies (1 Nov)

Everything but the screens lives in `apps/ios/JourneyKit`, a local Swift
package: the Jellyfin client, the library database and sync, the art
cache and the Keychain session. The app target holds only
`AppModel.swift` and `Views/`. The package also builds `journey`, a
command for testing against the real server without the simulator:
`mise run ios cli sync [--full] | stats | art <album id>`, with its
database in `apps/ios/build/cli`.

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
Run `orca emulator kill` when done.

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

## Roadmap

1. **Ship to the phone.** Done 1 Nov: builds go to TestFlight with
   `mise run ios testflight`.
2. **Sign in and sync.** Done 1 Nov: sign-in to sol's Jellyfin
   (`JELLYFIN_URL`, https://jellyfin.example; the account is
   in `JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`), the session in the
   Keychain, full and delta sync into the local database, album art
   cached by `ImageTags`. A stand-in screen shows the counts and the
   albums added most recently.
3. **Browse and search offline.** The three tabs, album and artist
   pages, search against the local database only.
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
