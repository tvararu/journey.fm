# iOS prior art (1 Nov)

Research for the step 3 screens and for mockups, gathered by claude from
published sources. `docs/ios.md` has the agreed UX rules and the data the
screens can show; these notes say what other music apps do and which of
it fits.

| File | Covers |
|---|---|
| [apple.md](apple.md) | Apple Music on iOS 26, the HIG, the SwiftUI APIs verified against Apple's docs |
| [spotify.md](spotify.md) | Home, Your Library, Search, album and artist pages, the players |
| [indie.md](indie.md) | Doppler, Albums, Marvis Pro and Plexamp: players for owned libraries |
| [jellyfin.md](jellyfin.md) | Manet, Finamp, Symfonium, Amperfy and others; Jellyfin endpoints and pitfalls |

Anything the researchers couldn't read at the source is marked
[INFERENCE] in the files.

## Where the sources agree

- **Stay stock.** Apple Music's iOS 26 layout is built entirely from
  public SwiftUI APIs. Manet, the best-liked iOS Jellyfin client, looks
  like Apple Music, and its reviews ask for features, never for a
  different look.
- **Library is the main screen; Home is secondary.** Spotify's Your
  Library carries over: chips for Albums and Artists, a sort menu, a
  list/grid toggle and a filter field, with the choices kept between
  launches. Its Home feed is mostly recommendations, which a 680-album
  library doesn't need.
- **Home is a few fixed shelves over local queries.** Marvis Pro,
  Finamp 1.0 and Plexamp all build Home from shelves defined by rules.
  Recently Added and Random Albums need only today's data. Recently
  Played, Forgotten and On This Day wait for play history (step 4) or
  release dates.
- **Album pages share one shape.** Cover, title, artist, a line with the
  year, genre, track count and length, then Play and Shuffle, then
  tracks. Show disc headings only on multi-disc albums, and More by this
  artist only when there is more.
- **Offline is a state of the library, not a separate place.** Browse
  everything from the local database, play what's downloaded, and mark
  download state on covers and rows (step 5).

## Decisions for the mockups

- **Tab order.** iOS 26 places a `Tab(role: .search)` at the trailing
  end, set apart from the others, as Apple Music does. So the tabs read
  Home, Library, then Search, not Spotify's Home, Search, Library.
- **Mini player.** Use `tabViewBottomAccessory(isEnabled:)`, hidden
  until something is queued, laid out by
  `tabViewBottomAccessoryPlacement` (inline when the tab bar minimises,
  expanded otherwise). Tapping it opens now playing as a sheet.
- **Minimising the tab bar.** Use `.onScrollDown` on Library's long
  lists and `.never` on Home. MacStories found switching tabs from the
  minimised bar hard to discover.
- **Search.** The Search tab searches the whole library: artists,
  albums and tracks, grouped by type. Library's own field only filters
  the list on screen. Both run on the phone.
- **Long lists.** An A–Z index for Artists and Albums was the top
  request in Manet's reviews. It's stock on iOS 26: `List` sections with
  [`sectionIndexLabel(_:)`](https://developer.apple.com/documentation/swiftui/view/sectionindexlabel(_:))
  and `listSectionIndexVisibility(_:)`, in lists only, not grids.

## Left out on purpose

- Discovery feeds, editorial shelves and AI playlists. Plexamp dropped
  its AI playlist feature as unreliable.
- Artwork-tinted backgrounds (Apple Music in iOS 26.4, Albums,
  Plexamp's UltraBlur) and theming engines. They need custom colour
  work.
- Swipe-up cover gestures, Home builders, saved smart filters.
- Codec badges on covers (Plexamp). Every file is FLAC, so a badge would
  carry no information. The bit depth and sample rate could earn a place
  on the album page once sync stores them.
