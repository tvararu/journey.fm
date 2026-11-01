# Spotify

Spotify's iOS app is a streaming and recommendation product, and most of its
Home and Search surfaces serve that. The parts that carry over to a single
person's owned library of about 680 albums are the Your Library model (filter
chips, sort, list/grid toggle, pins, library-scoped search), the action row on
collection pages, and the now playing view reached from a bar above the tab
bar. All of those map onto stock SwiftUI on iOS 26. Spotify's own design
writing is thin on album and artist page layout, so those items are marked
where they rest on inference.

## Sources

Read in full:

- [Get to Your Favorites Faster with Spotify's New Home Screen][home2020]
  (Spotify newsroom, 9 Mar 2020)
- [3 Icons to Know in Spotify Mobile's Refreshing New Look][icons2020]
  (Spotify newsroom, 27 Feb 2020)
- [New Features on Spotify's Home Hub][hub2021] (Spotify newsroom,
  22 Mar 2021)
- [New 'Your Library'][lib2021] (Spotify newsroom, 29 Apr 2021)
- [The Best Features of Spotify's New 'Your Library' Tab][lifehacker]
  (Lifehacker, 30 Apr 2021)
- [Spotify introduces mobile library redesign][xda] (XDA Developers,
  29 Apr 2021)
- [Spotify's New Experience Inspires Deeper Discovery][home2023] (Spotify
  newsroom, 8 Mar 2023)
- [Spotify Launches a Major Redesign with Home Screen Previews][thurrott]
  (Thurrott, 8 Mar 2023)
- [Spotify for mobile redesign looks a lot like TikTok][routenote]
  (RouteNote, 10 Mar 2023)
- [Desktop redesign: Your Library and Now Playing][desktop2023] (Spotify
  newsroom, 20 Jun 2023)
- [How Spotify Uses Design To Make Personalization Features
  Delightful][pzn2023] (Spotify newsroom, 18 Oct 2023)
- [Sort and filter][sortsupport], [Your Library][libsupport], [Now Playing
  view][npsupport], [Play Queue][queuesupport], [Search][searchsupport]
  (Spotify support pages)
- [Spotify Case Study][muze] (Muze, an unsolicited redesign case study;
  undated)

Tried and failed: the ACM paper on the Your Library redesign and change
aversion (dl.acm.org, HTTP 403), and a Spotify Community complaint thread
(page returned no body). Neither is cited below.

[home2020]: https://newsroom.spotify.com/2020-03-09/get-to-your-favorites-faster-with-spotifys-new-home-screen/
[icons2020]: https://newsroom.spotify.com/2020-02-27/3-icons-to-know-in-spotify-mobiles-refreshing-new-look/
[hub2021]: https://newsroom.spotify.com/2021-03-22/new-features-on-spotifys-home-hub-make-navigation-and-discovery-even-simpler/
[lib2021]: https://newsroom.spotify.com/2021-04-29/listeners-can-explore-their-spotify-collections-faster-and-easier-with-a-new-your-library-2/
[lifehacker]: https://lifehacker.com/the-best-features-of-spotifys-new-your-library-tab-1846799185
[xda]: https://www.xda-developers.com/spotify-library-redesign-improved-navigation/
[home2023]: https://newsroom.spotify.com/2023-03-08/new-home-page-scroll-clips-previews
[thurrott]: https://www.thurrott.com/music-videos/spotify/280284/spotify-launches-a-major-redesign-with-home-screen-previews
[routenote]: https://routenote.com/blog/spotify-for-mobile-redesign-tiktok-clone
[desktop2023]: https://newsroom.spotify.com/2023-06-20/spotify-desktop-experience-redesign-your-library-now-playing-views-customize/
[pzn2023]: https://newsroom.spotify.com/2023-10-18/how-spotify-uses-design-to-make-personalization-features-delightful/
[sortsupport]: https://support.spotify.com/us/article/sort-and-filter/
[libsupport]: https://support.spotify.com/us/article/your-library/
[npsupport]: https://support.spotify.com/us/article/now-playing/
[queuesupport]: https://support.spotify.com/us/article/play-queue/
[searchsupport]: https://support.spotify.com/us/article/search/
[muze]: https://www.muzedesign.com/spotify-case-study.html

## Patterns

Each entry: screen, what it does, why it works or fails, source, and whether
stock SwiftUI on iOS 26 can build it.

### Home: shortcuts grid on top, shelves beneath

- **Screen:** Home. The 2020 redesign put a dedicated space at the top of Home
  with six quick-access tiles for familiar content, under a time-of-day
  greeting ("Good morning" to "Good evening"). Below sit shelves: top
  podcasts, made-for-you playlists, discovery picks. [home2020]
- **Why it works:** it answers "resume what I know" before "show me
  something new". The 2023 post says shortcuts or recently played still sit
  at the top of Home after the feed changes. [home2023]
- **For journey.fm:** the six-tile shortcut block needs play history, which
  does not exist until step 4. Until then the honest top shelf is "recently
  added" (date added is available). Shelves of covers (new albums, by year,
  by genre) fit the available fields.
- **Stock build:** yes. `ScrollView` with `LazyHStack` shelves and a
  `LazyVGrid` of two columns for tiles, under a large navigation title. The
  time-of-day greeting is plain `Text`.

### Home: "Recently played" destination

- **Screen:** a history screen reachable from Home, up to three months of
  listening history, showing individual tracks as well as the albums they
  came from. [hub2021]
- **Why it works:** history is a browsable list, not only a shelf. Spotify's
  own case-study critic notes Recently Played appears on Home and again in
  Your Library, and questions whether it belongs in the library at all.
  [muze]
- **For journey.fm:** later, once history exists. Keep it on Home only.
- **Stock build:** yes. `NavigationLink` to a `List`.

### Home: preview feeds, DJ, smart shuffle, autoplay

- **Screen:** 2023 added vertical feeds of video and audio previews on Home
  and Search, plus an AI DJ and Smart Shuffle. [home2023] Press coverage
  called the previews TikTok-like; the preview plays whatever is on screen
  and tapping continues it as normal playback. [thurrott] [routenote]
- **Verdict:** exists to sell discovery of unfamiliar content. Irrelevant to
  a library you already own.
- **Stock build:** not applicable; needs custom paging video feeds.

### Your Library: filter chips

- **Screen:** Library tab. A row of filters at the top (album, artist,
  playlist, podcast; Downloaded for Premium). Choosing one narrows the list.
  [lib2021] [lifehacker] On mobile the filter row and a search icon sit at
  the top; the help page says to tap a filter or tap search to search the
  collection. [sortsupport]
- **Why it works:** one tab, one list, scoped by type. Downloaded as a chip
  is the offline answer. Critic's view: before the redesign the library
  mixed playlists, recents, radio, downloads and saved items with obscure
  logic, so users could not learn it. [muze] The chips fixed the mixing.
- **For journey.fm:** chips for Albums and Artists now; Downloaded after step
  5. Do not add a Playlists chip until playlists sync.
- **Stock build:** yes. A horizontal `ScrollView` of `Button`s styled as
  capsules, or a `Picker` with `.segmented` style for two or three options.
  A `Menu` is the other stock option. Custom chip look is only styling.

### Your Library: sort

- **Screen:** Library tab, sort control beside the filters. Options: recents,
  recently added, alphabetical, by creator. [sortsupport] [lifehacker] The
  app remembers sort and filter between sessions. [sortsupport] XDA notes
  there is no manual ordering on mobile. [xda]
- **Why it works:** a small, fixed menu and persistence.
- **For journey.fm:** title, artist, year, date added are all available;
  "recently played" waits for history. Persist the choice.
- **Stock build:** yes. `Menu` with a `Picker`, and `@AppStorage` for
  persistence.

### Your Library: list/grid toggle

- **Screen:** an icon at the top right of the Library toggles list and a
  grid of large cover, artist photo or logo tiles. The list stays; the grid
  does not replace it. [lifehacker] [lib2021] Support pages confirm the same
  toggle. [sortsupport]
- **Why it works:** covers are how an owner of 680 albums recognises things.
  The list stays denser for scanning by name.
- **Stock build:** yes. `List` and `LazyVGrid` with
  `GridItem(.adaptive(minimum:))`, switched by a toolbar `Button` and an
  `@AppStorage` value.

### Your Library: pinned items

- **Screen:** up to four items pinned to the top, via swipe right on a row
  or tap and hold then Pin. [lib2021] [lifehacker] [sortsupport]
- **Why it works:** a tiny, capped shortcut set. The cap of four keeps pins
  from turning into a second library.
- **For journey.fm:** a pin set needs only a local table of album ids. It is
  the only personalisation we can add before play history exists.
- **Stock build:** yes. `.swipeActions(edge: .leading)` and `.contextMenu`;
  a pinned `Section` at the top of the `List`. Capped at 4 is app logic.

### Your Library: scoped search

- **Screen:** the search icon in Library searches only the collection. On
  desktop Spotify's 2023 post says that before the redesign library search
  meant wading through the whole catalogue; now it is "Your Library"
  exclusively. [desktop2023]
- **For journey.fm:** the whole catalogue is the owned library, so global
  and library search are the same. Do not build two.
- **Stock build:** yes. `.searchable` on the Library stack, or on the Search
  tab (see below).

### Search: browse grid versus results; grouping by type

- **Screen:** Search tab. Spotify's browse grid of genre and mood tiles takes
  a lot of space; a critic argues the genre suggestions take excessive room
  and that Home and Search could merge. [muze] Results cover songs, albums,
  artists, playlists, genres, profiles. Typed prefixes (year:, genre:,
  label:, artist:, album:) narrow results. [searchsupport]
- **A top result card and per-type sections** are how Spotify lays results
  out; I did not find a primary source that describes this in words.
  [INFERENCE] from the app itself, not read.
- **For journey.fm:** an empty-state grid of genres is possible because
  genres exist, but with 680 albums a plain list of recent searches or
  genres is enough. Results grouped Artists, Albums, Tracks suit the data.
  Typed prefixes are a power feature that FTS5 could support, but nothing
  in stock iOS needs them.
- **Stock build:** yes. `Tab(role: .search)` with `.searchable`, results in
  a `List` with `Section`s. Genre grid as `LazyVGrid` in the empty state.
  An iOS 26 `.searchable` on a `Tab(role: .search)` puts the field with the
  tab bar ([INFERENCE] from Apple's iOS 26 behaviour, not read here).

### Album page: action row

- **Screen:** album and playlist pages. The 2020 refresh grouped actions
  (like, play, download) into one row in the middle of the screen, described
  as one-handed and responsive to device size, with a single green Shuffle
  Play button that includes the shuffle icon. Tracks show cover art in all
  views except Album view. [icons2020]
- **Why it works:** the same actions in the same place on every collection
  page. Muze's case study complained that Like and Follow kept moving and
  changing shape and sent the user to one place anyway. [muze]
- **For journey.fm:** title block, then one row: Play, Shuffle, and later
  Download. Track rows on an album page need no art, as Spotify itself
  omits it there.
- **Stock build:** yes. `HStack` of `Button`s with `.buttonStyle(.borderedProminent)`
  and `.bordered`; track `List`.

### Artist page layout

- No Spotify design source I could read describes the mobile artist page.
  Muze's case study says Artist Radio is buried behind a menu on the artist
  page and moves it to the top right corner. [muze]
- [INFERENCE] from the app: header image, play button, popular tracks,
  discography grouped by type, "appears on". None of that is cited here.
- **For journey.fm:** 181 of about 300 artists have one album, so a
  "popular tracks" block makes no sense; the page is a header and an album
  list. This is from the library facts in `docs/ios.md`.
- **Stock build:** yes. `List` with a header `Section`, or a `ScrollView`.

### Mini player and now playing

- **Screen:** a now playing bar sits just above the menu bar; tapping it
  opens the larger view. Controls: save, shuffle, repeat, queue, connect,
  with more under a three-dot menu. [npsupport] The queue opens from the
  bottom of the now playing view; reorder by drag handle, remove by swipe
  left, add by swipe right on a track. [queuesupport] On desktop the view is
  a sidebar with About the Artist, On Tour, Merch, Next in queue. [npsupport]
  [desktop2023]
- **Why it works:** one bar, one expanded view, queue one tap away. The
  desktop extras are artist-facing commerce and do not belong in a personal
  library.
- **Stock build:** yes. `tabViewBottomAccessory` for the bar; a `.sheet` with
  `.presentationDetents` for now playing; `List` with `.onMove` and
  `.swipeActions` for the queue. Dominant-colour backgrounds and custom
  scrubbers are custom work and are not needed.

## What matters for 680 owned albums

Useful:

- Library as chips plus sort plus grid toggle plus search.
- Pin cap of four.
- One consistent action row on album pages.
- A single shuffle/play affordance.
- Persisted sort and filter.

Streaming or recommendation only:

- Preview feeds, DJ, Smart Shuffle, autoplay, made-for-you shelves,
  canvases, tour dates, merch. [home2023] [desktop2023]
- Time-of-day greetings are cosmetic.

## Top 5 takeaways for journey.fm

1. **Copy the Library model, not the Home model.** Chips (Albums, Artists,
   later Downloaded), a sort menu, a list/grid toggle, search, all in one
   tab. All stock: `Menu`, `Picker`, `List`, `LazyVGrid`, `.searchable`.
   [lib2021] [sortsupport]
2. **Persist sort, filter and view mode.** Spotify does, and it makes the
   tab feel like yours. `@AppStorage`. [sortsupport]
3. **Pins capped at four** are the cheapest personalisation and need no
   history. `.swipeActions` plus a pinned `Section`. [lib2021]
4. **One action row on every collection page**, in the same place, with a
   single prominent Play or Shuffle. Spotify's own critic punishes shifting
   Like/Follow buttons. [icons2020] [muze]
5. **Until history exists, Home is shelves of covers by date added.** Do not
   fake the six-tile "jump back in" block; add it at step 4. Skip the
   discovery feeds entirely. [home2020] [hub2021]

Caveat: the 2021 library redesign was shipped after change-aversion research
(an ACM paper I could not open), and the Spotify Community thread of user
complaints did not load. Treat "what fails" claims above as limited to the
Muze critique and XDA's note about no manual order.
