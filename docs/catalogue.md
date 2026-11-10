# The catalogue

One canonical record per album, resolved from several sources, reviewed,
then written to the FLACs as tags. These are the rules it follows. They
were agreed while cataloguing one library of about 670 albums in late
2026, and the code encodes them.

## Layout it expects

The host keeps the library as `Music/<Artist>/<Album>/` under
`JOURNEY_LIBRARY`. An album's path, `Music/Artist/Album`, is its name
everywhere; its slug is the first 12 letters and digits of the artist
folder, a hyphen, and the first 16 of the album folder.

`data/` on the cataloguing machine holds:

- `inventory/`: the newest scan of the host. Every raw tag, STREAMINFO,
  block layout, picture and folder file in SQLite, images stored once by
  sha256. `mise run inventory` makes a new one.
- `raw/<slug>/`: every source response, whole and unmodified, with its
  fetch time, so other fields can be taken later without fetching again.
- `catalogue/<slug>.json`: the resolved record, each field with the
  source it came from and what the other sources said.
- `catalogue/covers/`, `previews/`: masters, embeds and thumbnails.

`records/` holds what people and agents decided, append-only: notes,
reviews, verdicts, overrides and the write log.

## Pipeline

`mise run prepare "Music/Artist/Album" ...` runs each album end to end:

1. **Fingerprints** on the host with `fpcalc`, looked up on AcoustID.
2. **Edition.** Candidates come from the files' MusicBrainz release and
   release group tags, or a search by artist and title when there are
   none. Each is scored on track lengths, catalogue number, barcode and
   AcoustID agreement. Identity goes by ID, not search, wherever an ID
   exists: in a ten-album trial, text search returned a different album
   six times and the wrong edition five more.
3. **Enrich**: the release group, Cover Art Archive and Discogs for the
   chosen release.
4. **Covers**: candidates fetched, one picked as master.
5. **Lyrics** from LRCLIB, matched on duration, synced preferred.
6. **Resolve** into `catalogue/<slug>.json`.

Then an album is reviewed like a pull request: accepted, or changes
requested with a message. Each review stores a fingerprint of the
proposal, so a record that changes after acceptance shows as such.
`mise run set` overrides any field by hand and beats every source.

## Sources per field

First source with a value wins.

| Field | Order |
|---|---|
| Title, album artist | MusicBrainz, then the files |
| Original date | MusicBrainz release group, then the files |
| Date (this edition) | MusicBrainz release, then the files |
| Label, catalogue number | MusicBrainz, Discogs, the files |
| Country, barcode, media, script | MusicBrainz, then the files |
| Release type | MusicBrainz release group |
| Genre | MusicBrainz, Discogs, the files |
| Credits | MusicBrainz relationships, never the files |
| Lyrics | LRCLIB |
| Cover | see below |

The resolver also reads saved RateYourMusic pages and Redacted torrent
details from `raw/<slug>/` when they are there, and ranks them first for
genres, release type and edition. Nothing in this repository fetches
either. Without them, genres are only as good as MusicBrainz's and
Discogs's, which is the weakest part of the result.

When sources disagree on edition or label but the audio is the same, the
files win: their MusicBrainz release, label and catalogue number.

Ratings are kept one per source, as numbers with vote counts, never
merged, and stay out of the review fingerprint so vote drift doesn't
unsettle an accepted album.

## Tags

Plain ASCII punctuation (straight quotes, plain hyphens) so titles type
and search easily; letters with diacritics are kept. Dates at the
highest resolution any source has. Upper-case standard names, one field
per value.

Album: `ALBUM`, `ALBUMARTIST`, `ALBUMARTISTSORT`, `RELEASETYPE` (one
field per type, Picard's form), `RELEASESTATUS`, `ORIGINALDATE` (first
release), `DATE` (this edition), `LABEL`, `CATALOGNUMBER` (repeated,
only from sources that agree on the label), `BARCODE`, `RELEASECOUNTRY`,
`MEDIA`, `SCRIPT`, `LANGUAGE` (ISO 639-3, repeated), `GENRE` (repeated),
`TOTALDISCS`, the MusicBrainz album, release group and album artist IDs,
`CATALOGUED_AT` and `CATALOGUE_FINGERPRINT`.

Track: `DISCNUMBER`, `TRACKNUMBER`, `TOTALTRACKS`, `TITLE`, `ARTIST`,
`ARTISTSORT`, `ARTISTS` (repeated), `ISRC`, the MusicBrainz recording,
track and artist IDs, `ACOUSTID_ID`, `LRCLIB_ID`, `LYRICS` (LRC text
when synced), and credits as one Picard tag per role and one field per
person: `COMPOSER`, `LYRICIST`, `WRITER` (when MusicBrainz doesn't say
which), `ARRANGER`, `CONDUCTOR`, `PERFORMER` (`Name (instrument)`),
`PRODUCER`, `ENGINEER`, `MIXER`, `REMIXER`.

RateYourMusic tags, written when a saved page exists. A name and its ID
share one field, `Name (ID)`, so they can't come apart the way two
parallel repeated tags could:

| Tag | Example |
|---|---|
| `RYM_ID` | 2279 |
| `RYM_URL` | https://rateyourmusic.com/release/album/black-sabbath/technical-ecstasy/ |
| `RYM_ARTIST` (repeated) | Black Sabbath (687) |
| `RYM_TYPE` | Album |
| `RYM_GENRE` (repeated) | Hard Rock (67) |
| `RYM_SECONDARY_GENRE` (repeated) | Groove Metal (472) |
| `RYM_SCENE` (repeated) | Palm Desert Scene (60775) |
| `RYM_DESCRIPTORS` | male vocalist, melodic, energetic |
| `RYM_RATING_SCORE` | 3.03 |
| `RYM_RATING_VOTES` | 9779 |
| `RYM_RANK` | #869 for 1976 |
| `RYM_FETCHED_AT` | 2026-10-30 |

Not written: the edition text, the ASIN, and the Discogs and Wikidata
IDs.

## Covers

`cover.jpg` in each folder is the master: fetched from the best source,
re-encoded at JPEG quality 95 with no chroma subsampling and the colour
profile kept, unless the original is already smaller. The untouched
original stays in `raw/<slug>/covers/`.

Candidates, in order: the Cover Art Archive for the exact release, then
releases with the same catalogue number and audio, the release group,
iTunes, Deezer, the files' own art. Prefer the art of the edition held,
then clean images with no borders, stickers or creases, then size. When
the files' own art or a digital copy shows the same picture as a scan,
it wins: scans often have colour casts.

The embedded copy is made from the master: Lanczos to 1200 px on the
long side, never upscaled, mozjpeg quality 88, progressive, 4:2:0, about
250 to 400 KB. A master under 2000 px can be upscaled to 3000 px through
ComfyUI, from the album page or `mise run upscale`; the original stays a
candidate.

## Writing

`mise run write <slug>... [--plan] [--backup] [--verify]` refuses any
album that isn't accepted. For the rest it:

1. stages each file's tags, lyrics, the embed and the master under
   `JOURNEY_META/writes/<slug>` on the host
2. replaces every tag and picture block with `metaflac`; the whole
   Vorbis comment block is rewritten from the catalogue, not patched,
   and the inventory keeps every original tag
3. adds ReplayGain with `metaflac --add-replay-gain`, recomputed, never
   carried over; albums mixing sample rates, bit depths or channel
   counts get track gain only
4. checks the audio with `flac -t`
5. moves the folder's old images to `JOURNEY_META/archive/` and installs
   the master as `cover.jpg`

`--plan` prints the tags without touching anything. `--backup` copies
the album to `JOURNEY_META/write-backup/` first, never over an earlier
copy. `--verify` reads every file back and compares it with the
catalogue. Each write is logged in `records/writes.jsonl` with the
album's fingerprint; an album is stale when its current fingerprint
differs.

## Jellyfin

Jellyfin reads the album year from `DATE` only and ignores most of the
rest, so the plugin in `apps/jellyfin` maps it: credits into `People`,
`ORIGINALDATE` into the year and premiere date, the RYM score into
`CommunityRating`, `RYM_ID`, `ACOUSTID_ID` and `LRCLIB_ID` into provider
IDs, `ALBUMARTISTSORT` into the album artist's sort name, and every
other tag into `Tags` as `KEY:Value`, on the album when all its tracks
share it. It also serves `GET /Journey/Archive?ids=a,b`: the given
tracks, or every track of a given album, as one uncompressed tar with
range support, which the phone uses for downloads.

`mise run jellyfin options` makes the library prefer `ARTISTS` to
`ARTIST` and hides the `KEY:Value` tags in the web UI; `refresh` reloads
the library from the tags; `clear` empties online metadata left on
albums. Turn the library's online fetchers off for albums and artists,
so pages show the tags alone.

Jellyfin only stacks disc folders named a prefix (`CD`, `Disc`, `Vol`)
then a number: `CD 1 Title` works, `CD#1 Title` shows as its own album.
