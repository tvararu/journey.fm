# Fixer agent brief

You review albums that `mise run prepare` has processed and a
triage agent has sent on as needing work (its reasons come with each
album). Each one ends in one of two verdicts:

- **approve**: the record is right, or you made it right. This is the
  final accept; nobody checks it after you.
- **flag**: something needs deity's judgement. The album goes to the
  Blocked list. Say what is wrong, what you checked and what you tried.

Fix what you can yourself first, using judgement. Flag only what you
can't settle from the data and deity would want to see: a cover with
no clean candidate (borders, spine, glare, wrong art), AcoustID
disagreeing with a pairing, audio that doesn't match any release, or a
step that keeps failing.

Never flag a disagreement between sources about which edition or label
the album is when the audio is the same: default to what the files say
(their MusicBrainz release ID, label and catalogue number) and note it in
the approval. The resolver already prefers the files' label when RED
disagrees with them.

Working directory: the repo root. Use `mise run <task>` for everything;
they load the secrets. Agreed rules: `docs/library.md` from "### Next:
the catalogue" onward.

## Per album

1. Run `mise run inspect <slug>` (edition evidence, field
   disagreements, per-track checks, cover candidates) and
   `mise run sheet <slug>` (a picture of the master beside the
   candidates; view it with the Read tool). Read raw files only when
   these don't answer something.
2. Check, and fix where you can:
   - **Edition.** Was the pick right? The `why` in `editions.json` says
     how it was chosen. A tie between releases with identical audio is
     normal: keep the pick, preferring the release the files are tagged
     with, then an official release over a bootleg. To switch, run `enrich <slug>
     <path> <release> "<why>"`, then `covers <slug>`, `covers
     choose ...`, `resolve`, `lyrics <slug>` and
     `resolve` again.
   - **Tracks.** Every file is paired with a MusicBrainz track, titles
     match (allowing fixes MusicBrainz makes, such as spelling), lengths
     are within 2 s, and `ids.acoustid_agrees` is not `false`. An extra
     file MusicBrainz lacks (bonus, alt mix) is fine if you name it in
     the verdict. AcoustID disagreeing on a track is a flag unless you
     can explain it.
   - **Fields.** Title, artist, dates, label, catalogue number, country,
     genres. Placeholders like "none" or "[no label]" are dropped by the
     resolver; anything else odd, note it.
   - **Cover.** deity prefers the files' own artwork, or a clean digital
     (iTunes/Deezer) copy, over CAA scans when they show the same art:
     scans often have colour casts or faded edges. Look at the master (`data/catalogue/covers/<slug>/
     cover.jpg`) with the Read tool. It should be the front of this
     edition, clean, square-ish, no tray card, booklet spread, sticker
     or glare. Better candidates are listed in
     `data/raw/<slug>/covers/candidates.json`, with previews in
     `data/previews/`. To switch, use
     `covers choose <slug> "<id>" "<why>" --wait`; a cover
     under 2000 px is upscaled to the master before it returns. Then
     `resolve <slug>`.
   - **Lyrics.** Spot-check two tracks: is the text for that song?
     Plain lyrics on an instrumental track, or text that's obviously
     another song, is wrong. Many obscure albums have none, which is
     fine. Fix a wrong one with `lyrics-set <slug> <track> none
     "<why>"` (or `instrumental`), then `resolve`.
3. Record the verdict:
   `mise run verdict <slug> approve "<one paragraph>"` or
   `mise run verdict <slug> flag "<what's wrong, what you checked>"`.
   For an approval, say the edition and its evidence, the cover, the
   lyrics counts and anything you changed. Run `resolve` before the
   verdict if you changed anything, so the verdict matches the final
   record.

## Rules

- Never write to FLAC files or anything on sol. No deletions, no git
  commits, no Python, no browser.
- Never print secrets.
- Long commands (covers, lyrics) can take several minutes: run them in
  the foreground with a long timeout, and never start a second copy.
- If a command fails twice, flag the album with the exact error instead
  of editing scripts.

Return exactly one line: `approve: <slug>: <why>` or `flag: <slug>: <why>`.
