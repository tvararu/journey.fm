# journey.fm

A catalogue and tagger for a FLAC library, a Jellyfin plugin that serves
its tags, and an iOS player that reads them.

It was built for one library of about 670 albums and one person, with
most of the code written by agents. It is published as it is, for anyone
who wants to read it or take parts of it.

```mermaid
flowchart LR
  flacs[FLACs on a host] -->|inventory| cat[Catalogue pipeline]
  src[MusicBrainz, Discogs, AcoustID,<br>Cover Art Archive, LRCLIB] --> cat
  cat --> view[Viewer: review and accept]
  view -->|write tags, art, ReplayGain| flacs
  flacs --> jf[Jellyfin + plugin]
  jf --> ios[iOS player]
```

## Parts

- `packages/catalogue`, `tools/tagging`: find each album's exact
  MusicBrainz edition, gather covers, credits and synced lyrics, resolve
  one record per album, and write it to the files with `metaflac`.
  Rules in [`docs/catalogue.md`](docs/catalogue.md).
- `apps/web`: the viewer. What the files say, what the catalogue
  proposes, what each source said, cover candidates, accept or request
  changes.
- `apps/jellyfin`: a Jellyfin plugin that maps the tags into Jellyfin's
  fields (credits, original dates, ratings, everything else as
  `KEY:Value` tags) and streams whole albums as one archive.
- `apps/ios`: a SwiftUI player for that Jellyfin. The library lives in a
  database on the phone, search is offline, playback is gapless and
  starts while a track is still downloading, and the whole library can
  be saved in the background. Design and roadmap in
  [`docs/ios.md`](docs/ios.md).

## Needs

- [mise](https://mise.jdx.dev), which installs Bun and .NET
- `ffmpeg`, `rsync` and `ssh` here; a host with the FLACs under
  `Music/<Artist>/<Album>/`, reachable over ssh, with `bun`, `flac`
  (for `metaflac`), `fpcalc` and `sqlite3`
- Jellyfin 12.4 for the plugin
- A Mac with Xcode 26 and XcodeGen for the app

## Getting started

```sh
cp mise.example.toml mise.local.toml    # then fill it in
mise install && bun install
mise run inventory                      # scan the host, pull the result
mise run prepare "Music/Artist/Album"   # resolve one album
mise run dev                            # viewer on localhost:8786
mise run write <slug> --plan            # the tags it would write
```

`mise tasks` lists the rest. For the app, copy
`apps/ios/Local.example.xcconfig` to `Local.xcconfig`, then `mise run
ios sim`. [`AGENTS.md`](AGENTS.md) describes how a batch of albums is
run with agents reviewing.

## Before you use it

- `mise run write` replaces every tag and picture in the files it is
  pointed at. Use `--plan` first and `--backup` always.
- The genres in the original library came from RateYourMusic, and some
  edition evidence from a tracker's rip logs. The code that fetched
  those is not here; the resolver still reads their saved responses,
  which is why both are named throughout. Without them, genres fall back
  to MusicBrainz, Discogs and the files.
- The history was rewritten before publishing to take out one library's
  records, so older commits don't build.
- Nothing here is packaged or versioned, and paths assume the layout
  above.

## Licence

MIT, see [`LICENSE`](LICENSE). The Jellyfin plugin in `apps/jellyfin`
links Jellyfin's GPL packages and is GPL-3.0-only, see
[`apps/jellyfin/LICENSE`](apps/jellyfin/LICENSE). The Iosevka fonts in
`apps/web/public/fonts` are under the SIL Open Font License.
