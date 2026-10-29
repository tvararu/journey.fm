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
- `docs/agents`: briefs for the triage and fixer agents

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
