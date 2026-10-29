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

1. Start `mise run prepare "Music/A/B" ...` in the background. It runs
   each album end to end and prints `PREPARED <slug>` as each lands. RYM
   runs serially in its own Orca tab; if it stalls on a security check,
   tell deity.
2. At once, start one `triage` subagent per album, giving each its slug
   and path. Each waits for its own album, then approves it (the final
   accept) or returns `needs_work` with reasons.
3. When the triage results are in, hand every `needs_work` album with
   its reasons to one `fixer` subagent. It approves or flags each;
   flagged albums go to Blocked, deity's only queue.
4. Report the totals, and every flag with its reason.

Slugs are `squash(artist dir)[:12]-squash(album dir)[:16]` (see
`packages/catalogue/prepare.ts`).
