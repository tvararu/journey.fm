# journey.fm

Private catalogue of a FLAC library. See `AGENTS.md` for the layout and
rules, and `docs/library.md` for how albums are resolved.

```sh
bun install
mise run pull         # data from sol
mise run dev          # viewer on localhost:8786
mise run prepare "Music/Artist/Album" ...   # see AGENTS.md: Running a batch
```
