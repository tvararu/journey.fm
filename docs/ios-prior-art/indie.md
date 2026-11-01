# Prior art: indie players for owned libraries

Doppler, Albums, Marvis Pro and Plexamp all treat the library as something the
listener owns, not a catalogue to be sold back to them. They share a few
habits: album art as the main unit, a "recently added" shelf in place of
recommendations, saved filters instead of an algorithm, and (in Plexamp's
latest release) explicit per-album codec and download markers. The most
useful findings for journey.fm are that a recommendation-free Home works if
it is a handful of rule-based shelves, that Plexamp already puts codec badges
and download state on album grids, and that the customisation-heavy parts of
these apps (Marvis sections, Albums Quick Actions) are the parts journey.fm
should not copy. Almost everything worth taking maps onto stock SwiftUI.

## Sources

Read in full or in part unless marked otherwise.

- [Doppler for Mac Offers an Excellent Album and Artist-Focused Listening
  Experience for Your Owned Music Collection](https://www.macstories.net/reviews/doppler-for-mac-offers-an-excellent-album-and-artist-focused-listening-experience-for-your-owned-music-collection/),
  MacStories, 29 Jul 2021 (date from the Brushed Type launch post below)
- [Doppler features](https://brushedtype.co/doppler/features/), Brushed Type,
  undated
- [Doppler MP3 & FLAC Player](https://apps.apple.com/au/app/doppler-mp3-flac-player/id1468459747),
  App Store listing, version history to 3.2 (3 Oct 2025) and an iOS 26 /
  Liquid Glass update
- [Albums 4.0: A Must-Have App for Music Lovers](https://www.macstories.net/reviews/albums-4-0-a-must-have-app-for-music-lovers),
  MacStories, April 2021 (inferred from the image paths; no date shown)
- [Albums for iPhone](https://www.macstories.net/reviews/albums-for-iphone),
  MacStories, 2014 (the original, unrelated app of the same name; read for
  its philosophy only)
- [Albums, the Apple Music player](https://www.albumstheapp.com/), developer
  site
- [Fourth Annual iOS Music Player Showcase: Marvis Pro](https://barrowclift.me/articles/fourth-annual-ios-music-player-showcase/12),
  7 Jan 2022
- [Plexamp v4.50.3: Ready or Not](https://forums.plex.tv/t/plexamp-v4-50-3-ready-or-not/942338),
  Plex forum release notes, 1 Sep 2026
- [Plexamp release notes](https://forums.plex.tv/t/plexamp-release-notes/221280?page=5),
  Plex forum, 2018 to 2025
- [Plexamp on the App Store](https://apps.apple.com/us/app/plexamp/id1500797510),
  listing and user reviews

Not found or not read: foobar2000 mobile, Flacbox, Evermusic. The 9to5Mac and
Verge searches returned nothing on these apps, so they are left out.

## Patterns

### 1. Albums first, one tap to play (Albums)

- **Screen:** the first tab is a grid of album art. Tapping an album starts
  playing its first track straight away. A toolbar menu picks grid, detail or
  list, and grid size.
- **Why:** MacStories calls the app opinionated for favouring albums over
  songs and playlists. The 2014 original went further: no filters, no
  playlists, just pick an album and play, because "there's a balance between
  searching your library and having fast and immediate access to favorites".
- **Caveat:** tap-to-play removes the chance to look before committing.
  Albums' answer is a long-press context menu for everything else.
- **Stock SwiftUI:** yes. `LazyVGrid` of cover buttons, `.contextMenu` for the
  actions. Whether a tap plays or opens the album page is a product choice;
  journey.fm's plan (navigate to the album page) is the safer default.

### 2. Library by category list (Albums, Marvis Pro)

- **Screen:** Albums' Library tab is a list of ways in: search, listening
  history, stats, then "a long list of categories". Marvis Pro's menu lists
  Artists, Albums, Songs, Playlists, Genres, Composers and Compilations.
- **Why:** a collector enters by what they know (artist, genre, decade), not
  by one flat grid. The user can reorder and hide entries in both apps.
- **Stock SwiftUI:** yes. A `List` of `NavigationLink` rows with SF Symbols in
  the Library tab. Reordering and hiding is `.onMove` and a toggle; skip it
  for v1 [INFERENCE].

### 3. Home without recommendations: rule-based shelves (Marvis Pro, Doppler, Plexamp)

- **Screen:** Marvis Pro's Home is built from "sections". Local-library types
  are Recently Played, Recently Added, Most Played, Top Rated, Loved,
  Forgotten and Library, each for songs, albums or artists. Doppler offers
  "Recently Added" as the album shortcut. Plexamp's new offline Home has
  "Recently Downloaded" and "Recently Added".
- **Why it works:** every shelf is a deterministic query, so the Home never
  shows something the listener cannot explain. Marvis Pro's "Forgotten" is
  the nearest thing to discovery, and it is just "not played in a while".
- **Why it can fail:** Marvis Pro's own reviewer notes the default Home is
  only "reasonable"; its value is the editable builder, which is far beyond
  journey.fm's scope.
- **For journey.fm:** with date added, year and genres available today, the
  shelves that need no play history are Recently Added, Random Albums (a
  reshuffle on pull-to-refresh), and "This week in your library by year"
  (see pattern 4). Forgotten and Most Played wait for step 4 (play history).
- **Stock SwiftUI:** yes. Vertical `List` or `ScrollView` of sections, each a
  horizontal `ScrollView` with `LazyHStack` of covers, plus a `NavigationLink`
  header ("Recently added >") to a full grid. Pull to refresh is `.refreshable`.

### 4. Time-based collections: Time Machine and anniversaries (Marvis Pro, Albums)

- **Screen:** a Marvis Pro user builds a "Time Machine" section from one
  rule per year (`Year is 2021`). Albums' Insights tab lists albums
  celebrating anniversaries, and, given a birth date, collections like "High
  School" and "My 30s".
- **Why it works:** a collector's library already has a timeline, and year is
  the one tag that is always present. This is the closest real analogue to
  "on this day" without any history data.
- **For journey.fm:** a "Year" list in Library (680 albums, so roughly a
  few dozen years) and a Home shelf for albums released on today's
  anniversary need only the year. An exact day needs a release date, which is
  not in the synced fields [INFERENCE: Jellyfin may have `PremiereDate`, not
  confirmed here].
- **Stock SwiftUI:** yes. A grouped `List` or `Section` per year; a SQL query
  for anniversaries.

### 5. Saved filters as first-class items (Albums Quick Actions, Marvis Smart Rules)

- **Screen:** Albums has 13 filter types and nine sort criteria, combinable
  with all/any, and "Quick Actions", saved filters in a strip near the bottom
  of the Albums view. Marvis Pro has the same idea as Smart Rules.
- **Why:** the reviewer's verdict is that this makes the app worth using "even
  if you prefer singles". It also costs complexity: Albums' own review lists
  a small, hard-to-tap toolbar menu as the one gripe.
- **Stock SwiftUI:** the filter UI is custom-heavy and not worth it. The
  cheap version is `Menu` with `Picker` items (sort by date added, year,
  title, artist) and `.searchable` tokens or scopes for genre. Skip rule
  builders.

### 6. Format and download state on the album grid (Plexamp 4.50.3)

- **Screen:** the release notes list "Album codec badges in large album
  grids" and "Albums and artists show download state, with a progress ring
  while downloading", plus a download indicator on chart rows. The 2018
  desktop notes also added "Display codec/bitrate on hover".
- **Why:** it is the only app in this set that puts format info on the browse
  surface instead of burying it in a track menu. For a lossless-first
  library, a badge also tells you when an album is a lossy outlier.
- **Caveat:** the notes do not say what the badge shows or whether it appears
  on small grids only for exceptions. I did not find a screenshot [INFERENCE:
  presumably FLAC/MP3/etc. text]. Doppler's listing names formats only as a
  feature and shows no per-album format.
- **Stock SwiftUI:** yes. `.overlay(alignment: .bottomTrailing)` on the cover
  with a small `Text` or `Image(systemName:)`, and `ProgressView` or a custom
  ring via `Gauge`/`Circle().trim`. Needs format data in the schema first:
  the synced fields today do not include codec or bit depth.

### 7. Offline mode as a switch that reshapes the whole app (Plexamp 4.50.3)

- **Screen:** an Offline switch in the source picker and Downloads header
  turns Plexamp into a downloads-only player. The Library keeps Artists,
  Albums, Complete Albums, Tracks and Playlists. The Home shows Recently
  Downloaded and Recently Added, and search covers only what is on the
  device. Queues are built locally, so "an album or shuffle-all is instant
  instead of a spinner".
- **Why:** the same screens work with a smaller set of data, so there is
  nothing new to learn on a plane. It beats greyed-out rows scattered across
  the app.
- **Stock SwiftUI:** yes. One `@Observable` flag that filters the GRDB
  queries, and a toggle or `Picker` in Library. No new navigation.

### 8. "Complete Albums" as its own view (Plexamp, Albums)

- **Screen:** Plexamp's offline Library has Albums and Complete Albums as
  separate entries. Albums' three-dot menu picks Full Albums, Incomplete
  Albums, Upcoming Albums or Singles.
- **Why:** with a partial download state, "which albums can I play fully
  offline" becomes the question the collector actually asks.
- **Stock SwiftUI:** yes, a filter on the same grid. Relevant from step 5.

### 9. Download keeps itself going (Plexamp "Keep Played Music")

- **Screen:** a setting with a storage cap. Played tracks stay on the device,
  oldest evicted first, tracks played offline count too. Library downloads
  sync newest first, so last night's album lands before the back catalogue.
- **Why:** removes the download button as a chore. journey.fm's plan already
  keeps played tracks cached (step 5), so this confirms the direction.
- **Stock SwiftUI:** the UI is a `Stepper` or `Picker` in a settings `Form`.
  The behaviour is a background `URLSession` job, not a UI matter.

### 10. Swipe up on the cover to reveal the tracklist (Albums)

- **Screen:** on iPhone, swiping up on Now Playing artwork separates it from
  the controls and reveals the tracklist, credits, statistics and album
  actions.
- **Why:** MacStories' favourite touch; power features stay out of sight.
- **Stock SwiftUI:** needs a custom gesture, which journey.fm has ruled out.
  The stock equivalent is a `.sheet` with `presentationDetents` for the
  queue, or a Now Playing toolbar `Menu`.

### 11. Artwork-tinted UI (Doppler, Albums, Plexamp)

- **Screen:** Doppler "dynamically changes itself to compliment the colours
  from your album artwork". Albums does it on a two-finger tap. Plexamp has
  UltraBlur backgrounds, now rendered on the GPU.
- **Why:** it makes cover art feel like the interface, which is the point of
  an album-first app. It is also the thing that most breaks "stock only".
- **Stock SwiftUI:** partly. A `.tint` from a dominant colour and a blurred
  `Image` background are plain SwiftUI, but extracting the colour is custom
  code. Out of scope for the first cut.

### 12. Search as a plain library search (Doppler, Albums)

- **Screen:** Doppler searches artists, albums and songs. Albums' Search tab
  uses the same search as Library and adds three shelves under the field:
  Recently Added, Recent Favorites and Recently Released.
- **Why:** an empty search screen is wasted; the shelves give a way in before
  you type. MacStories compares it to Apple's own Search tab.
- **Stock SwiftUI:** yes. `.searchable` with `.searchSuggestions` or content
  shown when the query is empty.

## Top 5 takeaways for journey.fm

1. **Build Home as three or four deterministic shelves, no algorithm.**
   Recently Added and Random Albums need only today's data. Add Forgotten and
   Most Played once play history lands. Marvis Pro's reviewer treats this as
   enough of a Home. Stock: horizontal `ScrollView` sections, `.refreshable`
   for re-rolling Random.
2. **Put the format and download state on the cover.** Plexamp 4.50.3 is the
   only app found that shows a codec badge in album grids and a download ring
   on albums and artists. For a lossless library, show a badge for anything
   that is not FLAC and a download marker from step 5. It needs codec and
   bit depth in the schema first. Stock: `.overlay` on the cover.
3. **Make offline a mode, not a scatter of disabled rows.** Plexamp's switch
   reuses Library, Home and search over the downloaded subset. journey.fm's
   local database already supports this. Stock: a flag in the GRDB queries.
4. **Use year as the browse axis.** A Year list in Library and an
   anniversary shelf on Home (Marvis "Time Machine", Albums anniversaries) are
   what an owned library offers that a streaming one does not. Stock: grouped
   `List`, SQL.
5. **Put sort and filter in a `Menu`, and leave out saved-filter builders.**
   Albums and Marvis show where the road ends up: it is powerful, and also the
   largest custom surface in either app. Sort by date added, year, artist and
   title, plus a Complete Albums filter later, covers what 680 albums need.

## Not worth copying

- Home builders, theming engines and per-section layout options (Marvis Pro).
- Swipe-up cover gesture and two-finger-tap theming (Albums), which are
  custom gestures.
- Sonic Sage and AI playlists: Plexamp removed them in 4.50.3, saying a
  feature that "sometimes returns a great playlist and sometimes returns
  nonsense isn't a feature, it's a slot machine".
