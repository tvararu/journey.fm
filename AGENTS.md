# journey.fm

A catalogue of the FLAC library on sol (`/mnt/pool/Music`), resolved from
MusicBrainz, RED, RYM, Discogs, AcoustID and LRCLIB, reviewed by agents,
and later written back as tags. `docs/library.md` holds the agreed rules.

## Layout

- `apps/web`: the catalogue viewer (Astro on Bun, port 8786)
- `packages/catalogue`: the pipeline and reviewer tools
- `tools/tagging`: scripts that run on sol, plus the RYM grabbers
- `records/`: reviews, verdicts, notes and RYM IDs (committed)
- `data/`: raw responses, covers, catalogue (gitignored, backed up to
  sol with `mise run push`)
- `.omp/agents`: the triage and fixer subagents

## Where things run

- sol keeps the FLACs and does inventory and fingerprinting over ssh;
  its `/mnt/pool/music-meta` is the backup of `data/`.
- t1 does the cataloguing: pipeline, data, ComfyUI upscales and RYM in
  Orca. The viewer runs from `apps/web/dist` as the systemd user unit
  `journey-web` on 127.0.0.1:8786 (rebuild and restart to update), and
  is published as the Tailscale Service `svc:journey`
  (`journey.example`).

## Rules

- Bun + TypeScript + mise only. No Python.
- Run everything through `mise run <task>`; tasks load the secrets.
- Never print a secret. Secrets are set by deity in their own terminal
  with `mise set --age-encrypt --prompt NAME`; list names only.
- Nothing is written to the FLACs or anything else on sol's music until
  the whole library is catalogued.
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

RYM comes first and is deity's job: `mise run rym [count]` names one
album at a time while deity finds its page in the Orca tab; the page is
saved once it is open. Albums are not marked In collection.
`mise run rym auto [count]` does the searching and saving itself, 10 to
20 s apart, and rings a bell when it needs deity: a security check, a
lost login, or an album it can't match. When claude runs it, claude
keeps `mise run rym alert` running beside it; that returns at the next
call for help, and claude asks deity with the ask tool, which shows a
blocking question in Orca. Claude's bell and desktop notification go to
t1, not to deity. `s` marks an album not on RYM
(`records/rym-skip.tsv`). Batches take only albums listed by `mise run
rym ready`, and `prepare` refuses any others.

RED is optional. While it is up, `mise run red` caches every album's
RED match in the background (about 2.3 s per request). `prepare` reads
that cache, fetches uncached albums if RED answers, and otherwise picks
the edition without RED. When RED is back, run `mise run red`, then
prepare again the albums `mise run red stale` lists.

Any album field can be set by hand with `mise run set <slug> <field>
<value>... --by deity [--why "<why>"]` (`--clear` undoes it). It goes to
`records/overrides.jsonl`, beats every source, and reopens the album for
triage, which treats a `deity` value as settled.

1. Start `mise run prepare "Music/A/B" ...` in the background. It runs
   each album end to end and prints `PREPARED <slug>` as each lands.
2. At once, start one `triage` subagent per album, giving each its slug
   and path. Each waits for its own album, then approves it (the final
   accept) or returns `needs_work` with reasons.
3. When every triage result is in, hand all the `needs_work` albums,
   each with its reasons, to a single `fixer` subagent in one task. Don't
   start a fixer per album. It approves or flags each; flagged albums go
   to Blocked, deity's only queue.
4. Review the batch yourself before reporting. Read the triage and fixer
   results and the `prepare` log, and look for problems that repeat:
   pipeline bugs, missing tools, races, brief wording that sent albums on
   for nothing, or verdicts that claim checks the agent didn't do. Fix
   them in code or in the briefs, verify the fix, and commit, so the next
   batch runs more smoothly.
5. Report the totals, every flag with its reason, and what the review
   changed.

Slugs are `squash(artist dir)[:12]-squash(album dir)[:16]` (see
`packages/catalogue/prepare.ts`).
