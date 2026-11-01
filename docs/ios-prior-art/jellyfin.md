# Jellyfin and Subsonic clients

Prior art from Manet, Finamp (including its redesign), Symfonium, Amperfy,
Feishin and Supersonic, read for how they lay out home, library and search
over a Jellyfin library, how offline works, what users praise or hit, and
which Jellyfin endpoints they use. The consistent picture: the best-liked
iOS client (Manet) is deliberately stock and Apple Music-shaped; the most
ambitious one (Finamp) added a customisable Home only after four years, as
an optional tab; users' loudest complaints are an alphabet index, playlist
bugs, and offline that silently loses features. Reddit blocked automated
reads, so r/jellyfin opinion below comes from App Store reviews, the
Jellyfin forum and press, not from Reddit itself.

## Sources

- https://tilosoftware.io/manet — Manet product page (v1.1.1, 30 Oct 2026)
- https://tilosoftware.io/manet/releases/v1.1.0 — Manet release notes
  (26 Oct 2026)
- https://apps.apple.com/us/app/manet-music/id6470928235 — Manet App Store
  page, reviews and version history (4.4 from 223 ratings when read)
- https://arne.me/blog/diy-music-streaming-with-nixos-and-jellyfin — Arne
  Bahlo, user account of Manet (1 Apr 2024)
- https://github.com/finamp-app/finamp/releases/tag/1.0.1 — Finamp 1.0
  release notes (11 Oct 2026)
- https://newreleases.io/project/github/finamp-app/finamp/release/0.9.24-beta
  — Finamp "Home Screen Update" notes (mirror of the GitHub release)
- https://raw.githubusercontent.com/finamp-app/finamp/redesign/lib/services/jellyfin_api.chopper.dart
  — Finamp's generated Jellyfin API client, `redesign` branch
- https://forum.jellyfin.org/t-offline-usecase-for-music — Jellyfin forum,
  offline music (Aug 2024)
- https://github.com/jellyfin/jellyfin/issues/6048 — Jellyfin issue:
  artist and album artist IDs do not match (2021, closed)
- https://jellyfin.org/posts/state-of-the-fin-2026-05-24/ — Jellyfin team
  update (24 May 2026)
- https://docs.symfonium.app/wiki/settings/settings-interface-home-page/ —
  Symfonium home page docs
- https://docs.symfonium.app/wiki/providers/jellyfin-media-provider-configuration/
  — Symfonium Jellyfin provider docs
- https://www.xda-developers.com/single-music-app-plex-jellyfin-navidrome/ —
  XDA on Symfonium (24 Mar 2026)
- https://www.xda-developers.com/clients-that-make-jellyfin-look-more-like-plex-and-spotify
  — XDA on Finamp and Symfonium (27 Jan 2026)
- https://github.com/BLeeEZ/amperfy — Amperfy README
- https://github.com/dweymouth/supersonic — Supersonic README
- https://feishin.net/ — Feishin marketing site. Third-party and ad-funded
  (it sells banner space), so treat feature claims with care.

## Patterns

### 1. Stock, Apple Music-shaped iOS client wins

- Screen: whole app (Manet).
- What: Manet advertises "native iOS technologies", "patterns you're already
  familiar with" and a Home screen. A user calls it very similar to Apple
  Music but "significantly better" for Jellyfin (arne.me). A review calls it
  "the Apple Music app (but better?) for Jellyfin users" (App Store).
- Why it works: no learning curve; the praise is for fit, not novelty. The
  complaints are never about the look, only missing features: no A-Z index,
  playlist rename and delete, themes.
- Stock SwiftUI: yes. `TabView`, `NavigationStack`, `List`.
- Source: Manet page, App Store reviews, arne.me.

### 2. Home as sections that read the library

- Screen: Home.
- What: Finamp's Home is quick-action buttons on top, then horizontal
  shelves of 20 items, each with a chevron to the full list, plus play and
  shuffle for the shelf. Each shelf is any tab plus sort plus filter (name,
  play count, date added, favourites only). Defaults are four actions and six
  sections, chosen from a survey of 300+ users. Manet's Home has a
  recently played section (it re-added genres there in 1.0.15).
- Why it works: the shelf is just a saved query, so it needs no server
  feature. Fails offline when it depends on play counts: Finamp says some
  sections are unavailable offline for that reason.
- Stock SwiftUI: yes. `ScrollView(.horizontal)` with `LazyHStack`, a
  `NavigationLink` on the header, `Button` for play. Customisation UI (long
  press to edit) is beyond the plan; fixed shelves are not.
- journey.fm now: "Recently added" (date added) and random or by-year shelves
  work from the local database; recently played waits for step 4.
- Source: Finamp 0.9.24 notes; Manet App Store version history.

### 3. Home is optional, library tabs stay primary

- Screen: tab structure.
- What: Finamp deliberately made Home "a tab", reorderable or hideable, so
  the app can still open on the album list; the 1.0 notes say the main
  screen is "still just a bunch of tabs".
- Why it works: the redesign did not punish users of the old album grid.
  Four years to ship Home also shows it is the costly part.
- Stock SwiftUI: yes. `TabView` with `Tab`.
- Source: Finamp 0.9.24 and 1.0 notes.

### 4. Alphabet index for big lists

- Screen: Library, Artists, Albums.
- What: the one iOS request repeated in Manet reviews: "the little A-Z
  sliders" like Apple Music, and "a nightmare to scroll endlessly until you
  get to S". Finamp ships scroll-to-letter and fixed it for album-artist
  sort in 0.9.24.
- Why it works: 680 albums by 300 artists is exactly the size where scroll
  alone hurts.
- Stock SwiftUI: [INFERENCE] iOS 26 `List` has a section index API
  (`.sectionIndexLabel`); not verified here. Needs sections by sort-name
  initial either way.
- Source: Manet App Store reviews; Finamp 0.9.24 notes.

### 5. Grid with text under the art

- Screen: Albums, shelves.
- What: Finamp moved titles and subtitles below the cover in grid mode
  because overlaid text had low contrast, and made the text smaller so the
  full title shows. Grid size is a slider that survives rotation; users
  choose grid or list per tab.
- Why it works: legibility on any cover. Cost: per-tab layout switches are
  settings sprawl.
- Stock SwiftUI: yes. `LazyVGrid` with adaptive `GridItem`. Per-tab toggle
  is an `@AppStorage` bool.
- Source: Finamp 0.9.24 notes.

### 6. Album page tinted by cover colour

- Screen: Album detail.
- What: Manet 1.1.0 extracts the album's primary colour and decorates the
  album view, and re-tuned it for dark mode in 1.1.1. Finamp offers adaptive
  theme colours on the player.
- Why it works: cheap sense of identity per album. Risk: contrast.
- Stock SwiftUI: partly. Showing a colour is stock (`.background`,
  `.tint`); extracting it is a small custom function (e.g. downsample and
  average). Optional, and the plan says no custom animation.
- Source: Manet releases v1.1.0, v1.1.1.

### 7. Offline: local database plus per-item download state

- Screen: Library, album and track rows, Downloads.
- What: Symfonium keeps a local database of the whole library, so favourites
  and playlist edits work offline and sync later; playlist modes are Offline
  first, Online first, Read only. Finamp's offline is "true offline": only
  downloaded tracks exist, no favourites, no playlist edits (Jellyfin forum,
  Aug 2024); 1.0 added an automatic offline mode and downloads by favourites,
  latest albums, all playlists, whole library, transcoded. Manet 1.1.0
  downloads all album and artist images for offline, and has "download full
  library from one button" as a review request.
- Why it works: journey.fm already holds the full catalogue locally, so it
  starts where Symfonium is, not where Finamp was. Browse works offline;
  the only thing downloads change is playability.
- Stock SwiftUI: yes for state (a `ValueObservation` column driving
  `Image(systemName: "arrow.down.circle")`), `.swipeActions` and
  `.contextMenu` for download and remove. The background `URLSession` is not
  UI.
- Source: Jellyfin forum thread; Finamp 1.0 notes; Manet release notes and
  reviews.

### 8. Explain failures: transcoding, connectivity

- Screen: Account or settings, download errors.
- What: Manet 1.1.1 says if the Jellyfin user is not allowed to transcode,
  songs could not be streamed or downloaded and the app did not say why; it
  now shows an error. Manet 1.1.0 added a connectivity label in Account.
- Why it works: silent failure on a self-hosted server looks like an app bug.
  For FLAC direct play this matters less, but a failed background download
  should surface.
- Stock SwiftUI: yes (`.alert`, `LabeledContent`).
- Source: Manet App Store version history, release notes.

### 9. Mixes and radio from the server

- Screen: Album and artist menus, Home.
- What: Finamp 1.0 has Instant Mixes for artists, albums, genres and
  playlists, plus Radio Mode (endless similar tracks), and an AudioMuse
  integration for sonic similarity. Supersonic offers artist radio, "depends
  on your server's support".
- Why it works or not: Jellyfin's own mix is metadata-based, so quality
  depends on tags; none of the sources reviews its quality.
- Stock SwiftUI: yes for the menu item (`.contextMenu`). The endpoint use is
  below.
- Source: Finamp 1.0 notes; Supersonic README.

### 10. Heavy customisation (Symfonium) is not the model

- Screen: Home, album, artist, search pages.
- What: Symfonium lets users show, hide and drag-reorder every home row, and
  save and share whole app styles. XDA praises "dense but refined". Its docs
  have a settings page for each of home, library, album, artist, genre,
  playlist and search.
- Why it fails for us: single-user, one design opinion. It also needs
  drag-reorder UI and a large settings surface.
- Stock SwiftUI: reorder is `EditButton` and `.onMove` in a `List`, so
  possible, but not wanted.
- Source: Symfonium docs; XDA.

## Jellyfin endpoints and API pitfalls

From Finamp's `redesign` API client (read) unless marked.

| Use | Endpoint and parameters |
|---|---|
| Latest albums | `GET /Users/{id}/Items/Latest` with `IncludeItemTypes`, `ParentId`, `Limit`, `GroupItems` |
| Sorted or filtered shelf | `GET /Users/{id}/Items` with `SortBy`, `SortOrder`, `Filters`, `IsFavorite`, `StartIndex`, `Limit` |
| Instant mix | `GET /Items/{id}/InstantMix` with `userId`, `limit` |
| Similar albums | `GET /Albums/{id}/Similar` with `userId`, `excludeArtistIds`, `limit` |
| Artist's albums | `GET /Users/{id}/Items` with `AlbumArtistIds`, `ArtistIds`, or `contributingArtistIds` |
| Letter jump | `NameStartsWith`, `NameStartsWithOrGreater`, `NameLessThan` on `/Items` |
| Search | `SearchTerm` on `/Items` (journey.fm searches locally instead) |

Pitfalls:

- Artist IDs can differ between `/Artists` and an album's `AlbumArtists`.
  In issue 6048 the same artist had one ID from the artist list and another
  on the album; a maintainer's advice was to filter albums with the ID from
  `/Artists` via `ArtistIds` or `AlbumArtistIds`, never `ParentId`, calling
  it inherited behaviour clients must work around. The issue was closed in
  Dec 2021; whether it still happens on current servers is [INFERENCE:
  untested]. journey.fm syncs album artists from album items, so it is only
  exposed if artist pages join through `/Artists` IDs; match by ID from the
  album's `AlbumArtists`, and check for orphans after a full sync.
- A client that rebuilds its own database "fully offline" cannot match the
  two IDs without a workaround, which is why that client fell back to
  fuzzy name and count matching (same issue).
- Jellyfin 10.11 had slow queries; performance work, including music
  libraries and homepage load times, was postponed to 12.0 (State of the Fin,
  May 2026; Finamp 0.9.24 notes). Matches journey.fm's `EnableTotalRecordCount=false` finding.
- Deprecated authorization methods are being disabled by default in 12.0;
  clients must use the current header scheme.
- Finamp tells users to re-download after upgrading so lyrics, gain and
  artist metadata are stored for offline use. Store those fields at sync
  time, not on demand.
- Finamp 0.9.24: servers on custom paths (`/jellyfin`) failed discovery.
  Normalise the base URL.
- Manet reviews: playlists merging across users, and playlist edits that
  report success but do nothing. Playlists are not synced in journey.fm yet;
  verify writes by re-reading.
- XDA reports Manet "would often stop playing altogether if the signal
  dropped for a moment" where Symfonium waits and reconnects. Relevant for
  step 4's route and stall handling.

## Top 5 takeaways for journey.fm

1. Stay stock. The best-loved iOS Jellyfin client is the one that looks like
   Apple Music; its reviews ask for features, never for another look.
   (Stock: yes.)
2. Add an A-Z index to Artists and Albums before polishing Home. It is the
   top repeated iOS request, and 680 albums needs it. (Stock: probably, with
   `.sectionIndexLabel` [INFERENCE: check on iOS 26].)
3. Home is fixed shelves over local queries: recently added now, recently
   played after step 4. Skip user-configurable rows. (Stock: yes.)
4. Because the whole catalogue is local, offline should mean "browse
   everything, play only what is downloaded", with per-row download state and
   clear errors. This is Symfonium's strength and Finamp's old weakness.
   (Stock: yes.)
5. Key everything by album and artist IDs from the albums themselves, and
   keep lyrics, gain and image data in the sync, not fetched later; both are
   Jellyfin pitfalls other clients paid for. (Not UI.)
