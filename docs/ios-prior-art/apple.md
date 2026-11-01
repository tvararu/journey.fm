# Apple prior art: Music, the iOS 26 design and the HIG

Apple Music on iOS 26 is the template that journey.fm's stock-SwiftUI
structure already follows: a floating Liquid Glass tab bar, a mini player
docked as the tab bar's bottom accessory, a trailing search tab, system
navigation bars and sheets. Every one of those pieces is a public API,
verified below against Apple's documentation. The one thing Music does that
stock SwiftUI cannot copy is the artwork-tinted album page and the full
now playing screen, which are custom drawing. Everything else (tab bar
minimising, accessory placement, search tab, scroll edge effect, glass
buttons) comes free from the SDK. Where a claim comes from memory rather
than a page I read, it is marked [INFERENCE].

## Sources

- [Build a SwiftUI app with the new design (WWDC25 323)](https://developer.apple.com/videos/play/wwdc2025/323/),
  Apple, June 2025. Transcript read in full.
- [Tab bars, HIG](https://developer.apple.com/design/human-interface-guidelines/tab-bars),
  updated 8 Jun 2026.
- [Search fields, HIG](https://developer.apple.com/design/human-interface-guidelines/search-fields),
  updated 8 Jun 2026.
- [Searching, HIG](https://developer.apple.com/design/human-interface-guidelines/searching),
  updated 8 Jun 2026.
- [Playing audio, HIG](https://developer.apple.com/design/human-interface-guidelines/playing-audio).
- [Lists and tables, HIG](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
  and [Collections, HIG](https://developer.apple.com/design/human-interface-guidelines/collections).
- API pages, all read:
  [`tabViewBottomAccessory(content:)`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)),
  [`tabViewBottomAccessory(isEnabled:content:)`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)),
  [`TabViewBottomAccessoryPlacement`](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement),
  [`TabBarMinimizeBehavior`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior),
  [`TabRole.search`](https://developer.apple.com/documentation/swiftui/tabrole/search),
  [`Tab(role:content:)`](https://developer.apple.com/documentation/swiftui/tab/init(role:content:)),
  [`searchToolbarBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)),
  [`searchable(text:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)),
  [`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)),
  [`backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()).
- [iOS and iPadOS 26: The MacStories Review, page 3](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3/),
  Federico Viticci, Sep 2025: tab bars, lists, search, menus.
- [Apple Music in iOS 26.4 has new design for albums, playlists, and more](https://9to5mac.com/2026/03/25/apple-music-in-ios-26-4-has-new-design-for-albums-playlists-and-more/),
  9to5Mac, 25 Mar 2026.
- [Apple Music in iOS 27 introduces new design changes in two key areas](https://9to5mac.com/2026/06/19/apple-music-in-ios-27-introduces-new-design-changes-in-two-key-areas/),
  9to5Mac, 19 Jun 2026 (artist pages; album pages announced, not yet shown).
- [Here's everything new for Apple Music in iOS 26](https://9to5mac.com/2025/09/24/heres-everything-new-for-apple-music-in-ios-26),
  9to5Mac, 24 Sep 2025 (pinned music, up to six items).
- [All the New Apple Music Features in iOS 26](https://lifehacker.com/tech/all-the-new-apple-music-features-in-ios-26-wwdc-2025),
  Lifehacker, 12 Nov 2025 (swipe the mini player to change track, iOS 26.1).
- [View albums, playlists, and more in Music on iPhone](https://support.apple.com/en-gb/guide/iphone/iphbddea0e5e/17.0/ios/17.0),
  Apple Support (iOS 17 version; Library categories, sort, filter).

I found no primary source describing the album page's section order (header,
tracks, "More by", related) in words, so that part is [INFERENCE] from using
the app and is flagged where it appears.

## Verified API names

| API | Availability | Notes |
|---|---|---|
| `.tabViewBottomAccessory { }` | iOS 26.0 | Above the tab bar when expanded, inline when minimised |
| `.tabViewBottomAccessory(isEnabled:) { }` | iOS 26.1 | Shows and hides the accessory; right for "nothing playing" |
| `@Environment(\.tabViewBottomAccessoryPlacement)` | iOS 26.0 | `.expanded` or `.inline` (enum `TabViewBottomAccessoryPlacement`) |
| `.tabBarMinimizeBehavior(_:)` | iOS 26.0 | `.automatic`, `.never`, `.onScrollDown`, `.onScrollUp`; iPhone only |
| `Tab(role: .search) { }` | `TabRole.search` iOS 18 | Needs `.searchable` on the `TabView`; first search-role tab owns search |
| `.searchable(text:placement:prompt:)` | iOS 16 | On `TabView` for the search tab |
| `.searchToolbarBehavior(.minimized)` | iOS 26.0 | After `.searchable`; bottom field collapses to a button |
| `.scrollEdgeEffectStyle(_:for:)` | iOS 26.0 | `.hard` or soft; default is automatic |
| `.backgroundExtensionEffect()` | iOS 26.0 | Mirrors and blurs content into the safe area; use once per screen |

From the WWDC transcript, not individually fetched from the docs (names as
spoken and in the sample code): `ToolbarSpacer`, `sharedBackgroundVisibility`,
`glassEffect`, `GlassEffectContainer`, the `.glass` and `.glassProminent`
button styles.

## Patterns

### 1. Floating tab bar with a trailing search tab

Screen: the whole app. The bar floats on Liquid Glass; in Music the tabs sit
at the leading end and Search is its own trailing button (HIG tab bars art).
Why it works: the bar is only as wide as its items (MacStories notes three-
and two-tab bars no longer look empty), and search is reachable from every
tab. The HIG says to choose the standard search tab to promote discovery and
the button appearance to resolve search quickly. Sources: HIG tab bars,
search fields; MacStories page 3.
Stock SwiftUI: yes. `TabView` with `Tab("Search", systemImage:
"magnifyingglass", role: .search)` plus `.searchable` on the `TabView`. The
system picks the standard or button look itself; [INFERENCE] the same code
gives Music's look.

### 2. Tab bar minimises on scroll, accessory docks inline

Screen: any scrolling tab. Scrolling down shrinks the bar to the active tab
as a small circle at the leading corner, the mini player slides in beside it
and search stays separate at the trailing corner. Tapping a tab or scrolling
to the top restores it (HIG). WWDC25 323 demos exactly this with the Music
playback view. Fails in one way: MacStories "not sold" because switching tabs
while minimised needs a long-press and swipe or an extra tap, which is hard
to discover. MacStories saw only one third-party app copy it.
Stock SwiftUI: yes. `.tabBarMinimizeBehavior(.onScrollDown)`. It's one
modifier, and `.never` is the opt-out if the extra tap is unwanted.

### 3. Mini player as the bottom accessory, two layouts

Screen: every tab. Expanded: full-width capsule above the tab bar. Inline:
compact controls between the active tab and the search button. The content
adapts by reading `tabViewBottomAccessoryPlacement`; Apple's own doc sample
shows playback controls for `.inline` and a slider view for `.expanded`.
Tap opens now playing. Source: WWDC25 323 (5:39 chapter), API pages, HIG tab
bars. Why it works: the player never competes with tab content or the
safe area and costs no custom layout.
Stock SwiftUI: yes. `.tabViewBottomAccessory(isEnabled: hasQueue) { MiniPlayer() }`
(iOS 26.1 for `isEnabled`); the tap-to-sheet is an ordinary `Button` and
`.sheet`. Swiping the mini player to change track (added in 26.1 per
Lifehacker) is a custom gesture and out of scope.

### 4. Large titles gone, scroll edge effect instead

Screen: lists such as Library. Content blurs and fades under the toolbar
rather than a pinned opaque bar; Liquid Glass buttons stay legible
(MacStories: "the iPhone's screen almost feels bigger"). WWDC25 323 says to
remove custom bar backgrounds because they break the effect.
Stock SwiftUI: yes and automatic. `.scrollEdgeEffectStyle(.hard, for: .all)`
only for dense UIs. Don't add `toolbarBackground` tints.

### 5. Library as a short list of categories with inline filter and sort

Screen: Library. A plain list (Playlists, Artists, Albums, Songs,
Downloaded), pins at the top (up to six items, iOS 26), then Recently Added.
Inside a category, swiping down reveals an inline filter field and a Sort
button (title, artist, recently added, recently played). The HIG explicitly
blesses this: global search is the tab, and an inline field filters the
library. Sources: Apple Support, 9to5Mac iOS 26 roundup, HIG search fields.
Stock SwiftUI: yes. `List` with `NavigationLink`, `.searchable(text:)`
inside the Library `NavigationStack` for local filtering, and a `Menu` with a
`Picker` or `Button`s for sort. Pinned items are a `LazyVGrid` section.
Pins need play history only for "Recently Played" sort, so they can wait.

### 6. Album and playlist pages with artwork-matched backgrounds

Screen: album detail. iOS 26.4 tints the track list background from the
artwork (9to5Mac: "not always an exact color match"). Layout, from
memory [INFERENCE]: large square cover, title, artist (tappable), genre and
year line, Play and Shuffle buttons, then the track list with track numbers
and a context menu per row, then release date, track count and total
duration, then "More by artist" and related shelves. 9to5Mac's iOS 27 piece
says Apple announced refreshed album and artist pages, with the artist photo
blending into the content and Play/star buttons under the name.
Stock SwiftUI: layout yes (`List` or `ScrollView` with `LazyVStack`, `Button`,
`.contextMenu`, a `Label` with `.foregroundStyle(.secondary)` for the meta
line, `.backgroundExtensionEffect()` for a cover that bleeds under the nav
bar on iPad or a wide banner). The artwork colour extraction itself needs
custom code (`UIImage` average colour); skip it: use a system background.

### 7. Disc grouping in the track list

Screen: multi-disc albums. [INFERENCE] Apple Music shows "Disc 1", "Disc 2"
section headers inside the track list when an album has more than one disc,
otherwise none. I found no source to cite for the exact design.
Stock SwiftUI: yes. `ForEach` over discs as `Section("Disc \(n)")` in a
`List`, only when the distinct disc count is above one.

### 8. Now playing as a sheet over the app

Screen: now playing. Full-height sheet with large artwork, scrubber, transport
and volume. HIG playing audio: use the system volume view
(`MPVolumeView`) and let people reroute audio; avoid repurposing system audio
controls; custom player controls only when the system can't do something
(for example custom skip intervals). WWDC25 323: partial-height sheets inset
with Liquid Glass, full-height go opaque; remove custom
`presentationBackground`; sheets can morph out of a source button with a
navigation zoom transition. Music's real now playing is a custom full
screen, but a `.sheet` with `presentationDetents([.large])` is the stock
equivalent.
Stock SwiftUI: yes. `.sheet`, `Slider` (iOS 26 sliders have `neutralValue`
and `ticks`), `MPVolumeView` via `UIViewRepresentable` (a tiny wrapper) or
`AVRoutePickerView`; the zoom transition from the mini player is
`matchedTransitionSource` and `.navigationTransition(.zoom)` [INFERENCE:
names from memory, not read on a docs page].

### 9. Search tab landing page, then results

Screen: Search. A landing page with browse categories before typing, then
grouped results; HIG: provide suggestions, search as you type, rank the best
matches first and categorise results, and show recent searches with a way to
clear them. Source: HIG search fields and searching.
Stock SwiftUI: yes. `.searchable`, `.searchSuggestions`, `.searchScopes` for
scope bars (Albums, Artists, Songs), results in `Section`s. With 680 albums
and no catalogue, the landing page can be recent searches or genres.

### 10. Lists: rounder, more spaced, grouped by system

Screen: any `List`. iOS 26 gives rounder cells, more inset groups and larger
glyphs by default (MacStories). HIG: prefer lists for text and use collections
(grids) for image-led content; keep the standard row or grid layout and avoid
custom layouts; use a disclosure chevron for navigation.
Stock SwiftUI: yes. `List`, `LazyVGrid` with `GridItem(.adaptive(minimum:))`,
no styling work needed.

### 11. Menus and swipe actions

Screen: any row. Menus put the glyph on the leading edge; the background is no
longer blurred behind a context menu (MacStories). Stock SwiftUI: yes.
`.contextMenu` with `Label`; `.swipeActions` for Play Next or Add to Queue
[INFERENCE: Music's own actions].

## Top 5 takeaways for journey.fm

1. **The Music structure is the stock structure.** `TabView` with Home,
   Library and `Tab(role: .search)`, `.tabViewBottomAccessory`, and
   `.tabBarMinimizeBehavior` are all public iOS 26 API that Apple's own
   WWDC demo and HIG tab bars page use for Music's mini player. No custom
   tab bar is needed or wanted.
2. **Use `tabViewBottomAccessory(isEnabled:)` and read
   `tabViewBottomAccessoryPlacement`.** Hide the accessory when nothing is
   queued (iOS 26.1 API) and render a compact transport row for `.inline` and a
   title plus artwork row for `.expanded`. Tapping it presents the now
   playing `.sheet`.
3. **Decide on minimise-on-scroll deliberately.** It gives the most content
   but MacStories flags the discoverability cost of tab switching. A 680-album
   library has long scrolling grids, so `.onScrollDown` pays off on Library;
   `.never` is the safe default for Home.
4. **Search lives in two places, as the HIG says.** The Search tab is
   global (with `searchable` on the `TabView` and scopes for Albums, Artists
   and Songs); Library filters in place with its own inline `.searchable`.
   Both run against the local database with no network.
5. **Album pages: copy the layout, skip the colour tinting.** Cover, title,
   artist, year and genre line, Play and Shuffle, tracks (with `Disc n`
   sections only for multi-disc albums), then totals from the synced tracks,
   then "More by artist" when the artist has another album. 181 artists have
   one album, so hide that shelf for them. Artwork-derived background colours
   (Music 26.4) are custom work: leave them out.
