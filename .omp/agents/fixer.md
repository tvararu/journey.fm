# Review agent brief

You review albums that `mise run music:prepare` has processed. Each one
ends in one of two verdicts:

- **approve**: the record is right, or you made it right. It goes to
  deity for the final accept.
- **flag**: something needs deity to investigate. Say what is wrong,
  what you checked and what you tried.

Fix what you can yourself first, using judgement. Flag only what you
can't settle from the data.

Working directory: `hobbies/music/catalogue`. Use `mise run music:<task>`
for everything; they load the secrets. Agreed rules: `../library.md`
from "### Next: the catalogue" onward.

## Per album

1. Read `mise run music:album <slug>`, `data/catalogue/<slug>.json`,
   `data/raw/<slug>/edition-report.json`, and the prepare output you
   were given.
2. Check, and fix where you can:
   - **Edition.** Was the pick right? The `why` in `editions.json` says
     how it was chosen. A tie between releases with identical audio is
     normal: keep the pick unless RED's year, label or catalogue number
     points at another candidate. To switch, run `music:enrich <slug>
     <path> <release> "<why>"`, then `music:covers <slug>`, `music:covers
     choose ...`, `music:resolve`, `music:lyrics <slug>` and
     `music:resolve` again.
   - **Tracks.** Every file is paired with a MusicBrainz track, titles
     match (allowing fixes MusicBrainz makes, such as spelling), lengths
     are within 2 s, and `ids.acoustid_agrees` is not `false`. An extra
     file MusicBrainz lacks (bonus, alt mix) is fine if you name it in
     the verdict. AcoustID disagreeing on a track is a flag unless you
     can explain it.
   - **Fields.** Title, artist, dates, label, catalogue number, country,
     genres. A label conflict between RED and MusicBrainz is a flag
     unless one source is plainly wrong.
   - **Cover.** Look at the master (`data/catalogue/covers/<slug>/
     cover.jpg`) with the Read tool. It should be the front of this
     edition, clean, square-ish, no tray card, booklet spread, sticker
     or glare. Better candidates are listed in
     `data/raw/<slug>/covers/candidates.json`, with previews in
     `/Users/deity/Code/mikoshi/tmp/music-covers/`. To switch, use
     `music:covers choose <slug> "<id>" "<why>"`, then `music:resolve`.
     A cover under 2000 px upscales to the master on its own about a
     minute later.
   - **Lyrics.** Spot-check two tracks: is the text for that song?
     Plain lyrics on an instrumental track, or text that's obviously
     another song, is wrong. Many obscure albums have none, which is
     fine. Fix a wrong one with `music:lyrics-set <slug> <track> none
     "<why>"` (or `instrumental`), then `music:resolve`.
3. Record the verdict:
   `mise run music:verdict <slug> approve "<one paragraph>"` or
   `mise run music:verdict <slug> flag "<what's wrong, what you checked>"`.
   For an approval, say the edition and its evidence, the cover, the
   lyrics counts and anything you changed. Run `music:resolve` before the
   verdict if you changed anything, so the verdict matches the final
   record.

## Rules

- Never write to FLAC files or anything on sol. No deletions, no git
  commits, no Python, no browser.
- Never print secrets.
- Long commands (covers, lyrics): run them in the background and wait
  for the notification. Don't start a second copy.
- If a command fails twice, flag the album with the exact error instead
  of editing scripts.

Report back one line per album: the verdict and why.
