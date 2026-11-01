# Dorsal as prior art

Read through on 1 Nov 2026 at upstream `74cb4bb` ("Set version=1.2
build=1"). Dorsal is an album-focused iOS player for Jellyfin with
CarPlay. The plan was to fork it, but the UX we want probably differs too
much, so it is prior art instead: we take ideas and code where they save
time.

`~/Code/dorsal` is a clone of the fork `a fork` (`origin`), with
`jaredreich/dorsal` as `upstream`. The two were identical on 1 Nov. The
licence is MIT, so code can be copied as long as the notice is kept.

## Shape

About 6,300 lines of Swift: SwiftUI, iOS 16, Swift 5, no tests. The one
package is SFBAudioEngine 0.12.1, which pulls in FLAC, Opus, Vorbis,
MP3 and other codec frameworks. Each service is a `static let shared`
object behind a protocol. Paths below are under
`MusicClient/MusicClient/`.

| Part | File (lines) | What it does |
|---|---|---|
| Jellyfin client | `Services/JellyfinService.swift` (510) | Auth, paged item fetches, stream and image URLs |
| Sync | `Managers/AlbumStateManager.swift` (296) | Full and quick sync, offline album list |
| Storage, search | `Managers/SearchManager.swift` (382) | JSON per album, in-memory indexes, Siri resolution |
| Downloads | `Managers/DownloadManager.swift` (944) | Background `URLSession`, pinning, cache sizes |
| Player | `Managers/AudioPlayerManager.swift` (699) | SFBAudioEngine, gapless, EQ, lock screen |
| CarPlay | `CarPlay/CarPlayTemplateManager.swift` (606) | Tab bar, lists, album detail, now playing |
| Siri | `../MusicClientIntents/`, `AppDelegate.swift` | `INPlayMediaIntent`, vocabulary donation |
| UI | `Views/` (about 1,700) | Library, album, now playing, settings |

## How it works

**Jellyfin.** Signs in with `POST /Users/AuthenticateByName` and sends a
`MediaBrowser Client=…, Device=…, DeviceId=…, Version=…, Token=…` header
as both `Authorization` and `X-Emby-Authorization` (the second for
servers older than 10.8). Lists come from `/Users/{id}/Items` in pages
of 500, with `MinDateLastSaved` for deltas. Audio is
`/Audio/{id}/stream?static=true` for the original, or
`/Audio/{id}/universal?audioCodec=aac&container=m4a&maxStreamingBitrate=…`
to transcode. Art is
`/Items/{id}/Images/Primary?maxHeight=500&quality=90&format=Jpg`. The
JSON is parsed by hand from `[String: Any]`, and the paging loop is
copied four times.

**Sync.** Only when the user starts it. A full sync fetches every album,
then every track in the background, writes one JSON file per album, and
deletes local albums the server no longer has. A quick sync fetches
albums and tracks changed since the last sync, adds the parent albums of
changed tracks, and refetches their track lists. It never deletes; that
is left to a full sync. When an album's `ImageTags.Primary` changes, its
cached art is deleted so it is fetched again.

**Storage.** Everything lives in the App Group container (not Caches), as
`Storage/albums/{id}.json`, `{id}.jpg` and `Storage/songs/{id}.{ext}`,
plus `albums.json` and `songs.json` indexes held in memory. Pinned and
recently played albums are in UserDefaults; credentials in the Keychain.
Search is a case- and diacritic-insensitive substring match over the
in-memory lists.

**Downloads.** A background `URLSession` with `sessionSendsLaunchEvents`,
and `handleEventsForBackgroundURLSession` wired to recreate the session
on relaunch. A continuation per track turns the delegate callbacks into
`async`. Albums download one track at a time, through a queue run by a
`Task` in the app. Any track that is played stays cached forever, and
album downloads pin the album against cache clearing.

**Player.** SFBAudioEngine's `AudioPlayer`, decoding with Core Audio. For
gapless playback it downloads the next track 60 s before the current one
ends and queues its decoder. A 10-band `AVAudioUnitEQ` sits between the
source and the mixer, and is reconnected when the engine rebuilds its
graph. It handles lock-screen info and remote commands, audio
interruptions, and `mediaServicesWereReset` (which CarPlay disconnects
cause), and saves the album, track and position on going to the
background.

**CarPlay and Siri.** A `CPTabBarTemplate` of library lists, album
detail and the now-playing template. It needs the
`com.apple.developer.carplay-audio` entitlement, which Apple grants per
App ID on request. Siri goes through an intents extension that hands off
to the app, resolves artist, album and song names against the local
metadata, and donates artist names as vocabulary.

## Where it falls short of our requirements

- **No playing while downloading.** `play(song:)` waits for the whole file
  before decoding. We would need an SFBAudioEngine input source that
  reads a file while it is still being written.
- **Bulk downloads stop in the background.** iOS keeps the current transfer
  running, but the queue that starts the next track is app code and does
  not run while the app is suspended. A library-wide download needs every
  task handed to the system up front.
- **Error pages saved as audio.** `didFinishDownloadingTo` never checks the
  HTTP status, so a 401 or 404 body is saved as a track, and an unknown
  MIME type is named `.m4a`.
- **Won't scale to the library.** `existingStorageUrl` lists the whole
  songs folder on every call, including during playback, and pin checks
  decode album JSON from disk.
- **Changed audio is never fetched again.** Quick sync rewrites the
  metadata but leaves the cached file alone.
- **Missing data.** No lyrics, genres, MusicBrainz IDs or database.
- **Upstream leftovers.** Quality defaults to 128 kbps AAC; the app group
  `group.com.jaredreich.shared` and session ID `com.jaredreich.download`
  are upstream's.

## What saves us time

1. **SFBAudioEngine and the player logic.** Gapless playback, the EQ in
   the graph, interruptions, audio-system resets after CarPlay, lock-screen
   info and controls: fiddly, and only shown up on a device. Take the
   approach without the download coupling.
2. **CarPlay templates and the Siri intent.** Mostly independent of the
   rest. Request the CarPlay entitlement early.
3. **The sync shape.** `MinDateLastSaved` on albums and tracks, parent
   albums of changed tracks, a full ID list for deletions, `ImageTags` for
   art. It matches the player design in `docs/library.md` and is proven
   against real servers. Rebuild it on a database instead of JSON files.
4. **Jellyfin details.** The dual auth header, the paging, the stream and
   image URL parameters. Rewrite with `Codable` types.
5. **Background session wiring.** `handleEventsForBackgroundURLSession` and
   recreating the session on relaunch: small, and easy to get wrong.

Not worth taking: the JSON-file storage, the download queue and the
SwiftUI views. New work is the database, a download manager built around
background `URLSession`, and the input source for playing while
downloading, with Dorsal's player and CarPlay code adapted on top.
