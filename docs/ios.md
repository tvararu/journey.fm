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

## Dependencies (1 Nov)

Vanilla Swift and Apple frameworks. A package only when it does
something specific that would be annoying to do ourselves. So far
nothing qualifies:

- Jellyfin: `URLSession` and `Codable`, no SDK
- Database and search: SQLite through the system `SQLite3` module
  (FTS5 for search, if the system build has it), or SwiftData
- Audio: Core Audio decodes FLAC natively (`AVAudioFile` opened a FLAC
  made with `afconvert` on 1 Nov), so `AVAudioEngine` with an
  `AVAudioPlayerNode` scheduling tracks back to back replaces Dorsal's
  SFBAudioEngine. It stays the fallback if play-while-downloading
  (step 6) proves annoying with the system APIs

## Roadmap

1. **Ship to the phone.** Paid membership, App Store Connect app, API
   key, first `mise run ios testflight` (the to-do in `AGENTS.md`).
2. **Sign in and sync.** Jellyfin sign-in, a local database of the whole
   library, a full sync then deltas (`MinDateLastSaved` on albums and
   tracks, parents of changed tracks, a periodic full ID list for
   deletions), art cached and refreshed by `ImageTags`.
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
