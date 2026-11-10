# journey.fm

A catalogue of a FLAC library: each album resolved from MusicBrainz,
Discogs, AcoustID, the Cover Art Archive and LRCLIB, reviewed by agents,
written back as tags, served by Jellyfin and played on the phone.
`docs/catalogue.md` holds the agreed rules.

Notes about the machines this checkout runs on, if there are any, are in
`AGENTS.local.md`, which git ignores. Read it when it exists.

## Layout

- `apps/web`: the catalogue viewer (Astro on Bun, port 8786)
- `apps/jellyfin`: the Jellyfin plugin (C#, .NET 10) that maps the
  catalogue's tags into Jellyfin's fields and serves album archives;
  `mise run jellyfin test | plugin`
- `apps/ios`: the iOS player (SwiftUI, XcodeGen `project.yml`, logic in
  the `JourneyKit` package); `mise run ios sim | device | log | test |
  format | cli | testflight`, described with the UX and roadmap in
  `docs/ios.md`
- `packages/catalogue`: the pipeline and reviewer tools
- `tools/tagging`: scripts that run on the host that holds the FLACs
- `records/`: reviews, verdicts, notes and overrides (append-only,
  ignored by git: they describe one library)
- `data/`: the inventory, raw responses, covers and the catalogue
  (ignored by git, backed up to the host with `mise run push`)
- `.omp/agents`: the triage and fixer subagents

## Where things run

- The host (`JOURNEY_HOST`) keeps the FLACs under `JOURNEY_LIBRARY` and
  does inventory, fingerprinting and tag writes over ssh. Its
  `JOURNEY_META` folder is the backup of `data/`.
- This machine does the cataloguing: the pipeline, `data/` and the
  viewer.
- A Mac builds the iOS app (Xcode, XcodeGen from Homebrew). The bundle
  identifier and team are in `apps/ios/Local.xcconfig`.

`mise.example.toml` lists every setting.

## Rules

- Bun + TypeScript + mise, Swift for the iOS app and C# for the Jellyfin
  plugin. No Python.
- Run everything through `mise run <task>`; tasks load the secrets.
- Never print a secret. Secrets are set by deity in their own terminal
  with `mise set --file mise.local.toml --age-encrypt --prompt NAME`;
  list names only.
- The FLACs change only through `mise run write`, and only for accepted
  albums.
- Any deletion needs explicit approval; moves go to archive folders.
- Never install software without asking.
- In records and the UI, the human is `deity`, agents are `claude`.
  No real names anywhere.
- Commits: Tim Pope style, subject at most 50 characters, imperative,
  capitalised, no trailing full stop; a one to three sentence body; no
  AI attribution. Push `origin main` after every commit.
- Wrap prose at 80 columns, sentence-case headings, almost no comments.

## Running a batch

The session coordinates; nothing spawns child agent processes.

Any album field can be set by hand with `mise run set <slug> <field>
<value>... --by deity [--why "<why>"]` (`--clear` undoes it). It goes to
`records/overrides.jsonl`, beats every source, and reopens the album for
triage, which treats a `deity` value as settled.

1. Start `mise run prepare "Music/A/B" ...` in the background. It runs
   each album end to end and prints `PREPARED <slug>` as each lands.
2. At once, start one `triage` subagent per album, giving each its slug
   and path. Each waits for its own album, then approves it (the final
   accept) or returns `needs_work` with reasons.
3. When every triage result is in, hand the `needs_work` albums, each
   with its reasons, to one `fixer` subagent at a time, at most 20
   albums per fixer, so it isn't overwhelmed. Don't start a fixer per
   album. Check in with deity after each fixer batch before starting the
   next. It approves or flags each; flagged albums go to Blocked,
   deity's only queue.
4. Review the batch yourself before reporting. Read the triage and fixer
   results and the `prepare` log, and look for problems that repeat:
   pipeline bugs, missing tools, races, brief wording that sent albums on
   for nothing, or verdicts that claim checks the agent didn't do. Fix
   them in code or in the briefs, verify the fix, and commit, so the next
   batch runs more smoothly.
5. Report the totals, every flag with its reason, and what the review
   changed.

Accepted albums are written with `mise run write <slug>... --backup`,
then checked with `--verify`.

Slugs are `squash(artist dir)[:12]-squash(album dir)[:16]` (see
`packages/catalogue/lib/albums.ts`).
