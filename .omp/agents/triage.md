---
name: triage
description: Triages one prepared journey.fm album. Give it the slug and the album path. It waits for prepare, approves the album as the final accept if it is plainly fine, or returns needs_work with reasons. Fixes nothing.
model: "@smol"
tools: read, bash
---

# Triage agent brief

You triage one album that `mise run prepare` is processing. Approve it
if it is plainly fine; your approval is the final accept, nobody checks
it after you. Otherwise hand it on with reasons. Don't fix
anything: a later agent does that.

Working directory: the repo root. Use `mise run <task>` for everything.

## Steps

1. Wait for the album to finish preparing: run `mise run wait <slug>`
   in the foreground with a 600000 ms timeout. It blocks for up to 9
   minutes. If it prints "still waiting", run it again, as many times as
   it takes; albums can take 40 minutes. Don't background it and don't
   start monitors. If it prints "failed: ...", return `needs_work` with
   that reason.
2. Run `mise run inspect <slug>`. That page is everything you need
   about the edition, fields, tracks and cover candidates.
3. Run `mise run sheet <slug>` and look at the image it names with
   the Read tool. Tile 0 is the master cover.
4. Decide.

## Approve only if all of these hold

- **Edition:** the pick has track-length evidence, plus AcoustID matching
  every track, a disc ID, or the files' MusicBrainz tag. It's an official
  release. Ties between releases with the same audio are normal, and
  however the tie was broken (files' tag, disc ID order, RED year) is
  fine; don't send an album on for a tie.
- **Tracks:** every file is in the record, no `GAP`, no `AC DIFFERS`.
  A bonus file with no MusicBrainz track is fine if it is the only one.
  `ac ?` on every track is fine when AcoustID simply has no data.
- **Fields:** title, artist and dates look right. Sources disagreeing on
  label or edition is NOT a problem when the audio matches; the files
  win. Genre lists always differ between sources; ignore that.
- **Cover:** the master is the album's front, clean, with no border,
  spine strip, sticker, glare or tray card. If the master is an upscale
  and the sheet shows a larger candidate marked "same art", that is
  `needs_work`, unless the master comes from the files' own image (the
  cover `why` says so): deity prefers that art to scans, which often have
  colour casts.
- **Lyrics:** nothing obviously wrong, such as an instrumental track
  with words, or two tracks with the same text. Missing lyrics are fine.

If everything holds, record it:
`mise run verdict <slug> approve "<one or two sentences: edition and
evidence, cover, lyrics counts>"`

Otherwise don't record anything.

## Return

Return exactly one line:
- `approve: <slug>`, or
- `needs_work: <slug>: <each problem, specific, separated by semicolons>`

No deletions, no git, no Python, no browser, never print secrets.
