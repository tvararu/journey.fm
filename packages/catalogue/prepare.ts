import { existsSync, readFileSync } from "node:fs";

import { album as lookupAcoustid, prints } from "./acoustid";
import { edition as runEdition } from "./edition";
import { enrich } from "./enrich";
import { albumOf, rymGrabbed, rymSkipped, yearOf, type Album as Base } from "./lib/albums";
import { files } from "./lib/inventory";
import { CATALOGUE, META, PREVIEWS, RAW, SCRIPTS, TAGGING } from "./lib/paths";
import { load } from "./lib/raw";

type Candidate = { how: string; id: string; date: string | null; evidence: string[]; lengths: string };
type Cover = { id: string; source: string; types: string[]; width: number; height: number; path: string };
type Release = { media: { tracks?: { recording?: { id: string } }[] }[] };
type Album = Base & { log: string[] };

const HERE = SCRIPTS;
const SOL_BUN = "/home/user/.local/share/mise/installs/bun/latest/bin/bun";
const COVER_TIERS = [
  "Cover Art Archive (release)", "Cover Art Archive (same catalogue number)", "Cover Art Archive (release group)",
  "iTunes", "Deezer", "files (folder)", "files (embedded)",
];

const paths = Bun.argv.slice(2);
if (!paths.length) {
  console.error('usage: prepare "Music/Artist/Album" ...');
  process.exit(1);
}

function run(cmd: string[], cwd = HERE): string {
  const p = Bun.spawnSync(cmd, { cwd, stderr: "pipe", stdout: "pipe" });
  if (p.exitCode !== 0) throw new Error(`${cmd.slice(0, 3).join(" ")} failed: ${p.stderr.toString().slice(-600)}`);
  return p.stdout.toString();
}

async function runAsync(cmd: string[], cwd = HERE, env: Record<string, string> = {}): Promise<{ code: number; out: string }> {
  const p = Bun.spawn(cmd, { cwd, env: { ...process.env, ...env }, stderr: "pipe", stdout: "pipe" });
  const [out, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
  return { code, out: out + err };
}

const albums: Album[] = paths.map((path) => ({ ...albumOf(path), log: [] }));
const skipped = rymSkipped();
const noRym = albums.filter((a) => !rymGrabbed(a.slug) && !skipped.has(a.path));
if (noRym.length) {
  console.error(`no RYM page and not marked "not on RYM"; run mise run rym first:\n${noRym.map((a) => `  ${a.path}`).join("\n")}`);
  process.exit(1);
}
const say = (a: Album, line: string) => {
  a.log.push(line);
  console.log(`${a.slug}: ${line}`);
};

function fingerprints(): void {
  run(["rsync", "-a", "sol:/mnt/pool/music-meta/fingerprints/", `${META}/fingerprints/`]);
  const have = prints();
  const missing = albums.filter((a) => files(a.path).some((f) => !have.has(`${a.path}/${f.relpath}`)));
  if (!missing.length) return;
  run(["scp", "-q", `${TAGGING}/fingerprint.ts`, "sol:catalogue/fingerprint.ts"]);
  const q = (x: string) => `'${x.replaceAll("'", "'\\''")}'`;
  const script = `cd ~/catalogue && ${SOL_BUN} fingerprint.ts /mnt/pool/music-meta/fingerprints/music.jsonl ${missing.map((a) => q(a.path)).join(" ")}\n`;
  const p = Bun.spawnSync(["ssh", "sol", "bash", "-s"], { stdin: Buffer.from(script), stderr: "pipe", stdout: "pipe" });
  if (p.exitCode !== 0) throw new Error(`fingerprinting on sol failed: ${p.stderr.toString().slice(-400)}`);
  run(["rsync", "-a", "sol:/mnt/pool/music-meta/fingerprints/", `${META}/fingerprints/`]);
}

function acoustidHits(slug: string, rid: string): [number, number] {
  const rel = load(slug, `mb_release_${rid}`) as Release | null;
  const ac = (load(slug, "acoustid") ?? {}) as Record<string, { score: number; recordings: string[] }[] | null>;
  const recs = new Set((rel?.media ?? []).flatMap((m) => (m.tracks ?? []).map((t) => t.recording?.id)));
  const heard = Object.values(ac).filter((m): m is NonNullable<typeof m> => !!m?.length);
  const hits = heard.filter((ms) => ms.some((m) => m.score >= 0.8 && m.recordings.some((r) => recs.has(r))));
  return [hits.length, heard.length];
}

async function edition(a: Album): Promise<boolean> {
  const [, looked] = await Promise.all([runEdition(a.slug, a.path), lookupAcoustid(a.slug, a.path)]);
  if (looked.missing.length) say(a, `AcoustID: no fingerprint for ${looked.missing.length} files`);
  const report = load(a.slug, "edition-report") as { candidates: Candidate[]; red?: { year?: number }; red_status?: string } | null;
  if (report?.red_status === "unavailable") say(a, "RED: not answering; edition picked without it (mise run red, then prepare again)");
  const cands = report?.candidates ?? [];
  if (!cands.length) {
    say(a, "edition: no candidates; needs a release picked by hand");
    return false;
  }
  const scored = cands.map((c) => {
    const [hit, of] = acoustidHits(a.slug, c.id);
    const ev = [...c.evidence, ...(of && hit === of ? [`AcoustID ${hit}/${of}`] : [])];
    const release = load(a.slug, `mb_release_${c.id}`) as { status?: string; media?: { format?: string }[] } | null;
    const vinyl = (release?.media ?? []).some((m) => /vinyl/i.test(m.format ?? ""));
    const heard = c.evidence.includes("track lengths") || (of > 0 && hit === of);
    return { ...c, ev, hit, of, official: release?.status === "Official", cd: heard && !vinyl, matched: c.evidence.includes("track lengths") };
  });
  const t0 = files(a.path)[0]!.tags;
  const tagged = t0["MUSICBRAINZ_ALBUMID"];
  const fileYear = yearOf(t0);
  const day = (c: Candidate) => Number((c.date ?? "").replace(/-/g, "").padEnd(8, "9")) || 99999999;
  const rank = (c: (typeof scored)[number]) => [
    Number(c.official), Number(c.cd), Number(c.matched), c.ev.length, c.hit,
    Number(c.id === tagged), Number(c.how === "discid"), Number(c.ev.includes("RED year")),
    Number(!!fileYear && Number((c.date ?? "").slice(0, 4)) === fileYear), -day(c),
  ];
  const BREAKERS = ["the files' MusicBrainz tag", "disc ID order", "RED year", "the files' year", "earliest date"];
  const cmp = (x: number[], y: number[]) => x.reduce((d, v, i) => d || y[i]! - v, 0);
  scored.sort((x, y) => cmp(rank(x), rank(y)));
  const best = scored[0]!;
  const tied = scored.filter((c) => c !== best && c.official === best.official && c.cd === best.cd && c.matched === best.matched && c.ev.length === best.ev.length && c.hit === best.hit);
  const decided = tied.length ? rank(best).slice(5).findIndex((v, i) => v !== rank(scored[1]!).slice(5)[i]) : -1;
  const breaker = tied.length
    ? `; tied on evidence with ${tied.map((c) => `${c.id.slice(0, 8)} (${c.date ?? "?"})`).join(", ")}, broken by ${BREAKERS[decided] ?? "MusicBrainz order"}`
    : "";
  if (!best.ev.length) {
    say(a, `edition: no candidate has track-length or AcoustID evidence (best ${best.id.slice(0, 8)}: ${best.lengths}); needs a release picked by hand`);
    return false;
  }
  const why = `auto-picked: ${best.ev.join(", ")}; ${best.lengths}${breaker}`;
  await enrich(a.slug, a.path, best.id, why);
  say(a, `edition: ${best.id} (${best.date ?? "?"}) ${why}`);
  return true;
}

const SAME_ART = 0.35;

async function thumb(path: string): Promise<Uint8Array> {
  const p = Bun.spawn(["ffmpeg", "-nostdin", "-v", "error", "-i", `${META}/${path}`, "-vf", "scale=24:24:flags=area,format=gray", "-frames:v", "1", "-f", "rawvideo", "-"], { stdout: "pipe", stderr: "ignore" });
  return new Uint8Array(await new Response(p.stdout).arrayBuffer());
}

function difference(a: Uint8Array, b: Uint8Array): number {
  if (a.length !== b.length || !a.length) return Infinity;
  const z = (v: Uint8Array) => {
    const m = v.reduce((x, y) => x + y, 0) / v.length;
    const sd = Math.sqrt(v.reduce((x, y) => x + (y - m) ** 2, 0) / v.length) || 1;
    return [...v].map((x) => (x - m) / sd);
  };
  const x = z(a);
  const y = z(b);
  let s = 0;
  for (let i = 0; i < x.length; i++) s += Math.abs(x[i]! - y[i]!);
  return s / x.length;
}

async function cover(a: Album): Promise<void> {
  const kept = existsSync(`${CATALOGUE}/covers.json`)
    ? (JSON.parse(readFileSync(`${CATALOGUE}/covers.json`, "utf8")) as Record<string, { chosen: { source: string; width: number; height: number } }>)[a.slug]
    : undefined;
  if (kept) {
    say(a, `cover: kept the master already chosen, ${kept.chosen.source} ${kept.chosen.width}x${kept.chosen.height}`);
    return;
  }
  const cands = JSON.parse(readFileSync(`${RAW}/${a.slug}/covers/candidates.json`, "utf8")) as Cover[];
  const ratio = (c: Cover) => Math.max(c.width, c.height) / Math.min(c.width, c.height);
  const usable = cands.filter((c) => COVER_TIERS.includes(c.source) && (c.types.includes("Front") || !c.types.length) && ratio(c) <= 1.2);
  const square = usable.filter((c) => ratio(c) <= 1.05);
  const fronts = square.length ? square : usable;
  const typed = (c: Cover) => Number(!c.types.includes("Front"));
  fronts.sort((x, y) => COVER_TIERS.indexOf(x.source) - COVER_TIERS.indexOf(y.source) || typed(x) - typed(y) || y.width * y.height - x.width * x.height);
  const edition = fronts[0];
  if (!edition) {
    say(a, "cover: no front candidate; pick one by hand");
    return;
  }
  let c = edition;
  let why = `auto-picked: ${c.source} front, ${c.width}x${c.height}`;
  const own = fronts.filter((x) => x.source.startsWith("files") && Math.min(x.width, x.height) >= 500 && x !== edition)
    .sort((x, y) => y.width * y.height - x.width * x.height);
  if (!edition.source.startsWith("files") && own.length) {
    const mine = await thumb(edition.path);
    for (const x of own) {
      const d = difference(mine, await thumb(x.path));
      if (d <= SAME_ART) {
        why = `auto-picked: the files' own ${x.source} image ${x.width}x${x.height}, the same art as the ${edition.source} front (difference ${d.toFixed(2)}); deity prefers the art already in the files over scans`;
        c = x;
        break;
      }
    }
  }
  if (Math.max(c.width, c.height) < 2000) {
    const mine = await thumb(c.path);
    const big = fronts.filter((x) => Math.max(x.width, x.height) > Math.max(c.width, c.height) &&
      (c === edition || x.source === "iTunes" || x.source === "Deezer"))
      .sort((x, y) => y.width * y.height - x.width * x.height);
    for (const x of big) {
      const d = difference(mine, await thumb(x.path));
      if (d <= SAME_ART) {
        why = `auto-picked: ${x.source} ${x.width}x${x.height}, the same art as the ${c.source} front (${c.width}x${c.height}, difference ${d.toFixed(1)}) at full resolution`;
        c = x;
        break;
      }
    }
  }
  const { code, out } = await runAsync(["bun", `${SCRIPTS}/covers.ts`, "choose", a.slug, c.id, why, "--wait"]);
  if (code !== 0) throw new Error(`covers choose failed: ${out.slice(-400)}`);
  say(a, `cover: ${c.source} ${c.width}x${c.height}${c !== edition ? ` (same art as the ${edition.width} px edition front)` : ""}${out.includes("upscaling") ? ", upscaling to master" : ""}`);
}

class Gate {
  private free: number;
  private waiting: (() => void)[] = [];
  constructor(n: number) {
    this.free = n;
  }
  async run<T>(fn: () => Promise<T>): Promise<T> {
    if (this.free > 0) this.free--;
    else await new Promise<void>((r) => this.waiting.push(r));
    try {
      return await fn();
    } finally {
      const next = this.waiting.shift();
      if (next) next();
      else this.free++;
    }
  }
}

const coverGate = new Gate(6);
const lyricsGate = new Gate(8);

async function album(a: Album): Promise<boolean> {
  const times: Record<string, number> = {};
  const step = async <T>(name: string, fn: () => Promise<T>): Promise<T> => {
    const t = Date.now();
    try {
      return await fn();
    } finally {
      times[name] = Math.round((Date.now() - t) / 1000);
    }
  };
  const marker = (extra: Record<string, unknown>) =>
    Bun.write(`${RAW}/${a.slug}/prepared.json`, JSON.stringify({ at: new Date().toISOString(), log: a.log, path: a.path, slug: a.slug, times, ...extra }, null, 1));
  try {
    if (!(await step("edition", () => edition(a)))) {
      await marker({ failed: "no edition picked" });
      console.log(`PREPARED ${a.slug} (failed)`);
      return false;
    }
    await step("covers", () => coverGate.run(async () => {
      const r = await runAsync(["bun", `${SCRIPTS}/covers.ts`, PREVIEWS, a.slug]);
      if (r.code !== 0) throw new Error(`covers failed: ${r.out.slice(-400)}`);
      await cover(a);
    }));
    run(["bun", `${SCRIPTS}/resolve.ts`, a.slug]);
    await step("lyrics", () => lyricsGate.run(async () => {
      let ly = await runAsync(["bun", `${SCRIPTS}/lyrics.ts`, a.slug]);
      for (let retry = 1; retry <= 3 && ly.code !== 0; retry++) {
        await Bun.sleep(20_000 * retry);
        ly = await runAsync(["bun", `${SCRIPTS}/lyrics.ts`, a.slug]);
      }
      const lines = ly.out.split("\n").filter((l) => l.startsWith(`${a.slug} `));
      const count = (k: string) => lines.filter((l) => l.includes(`-> ${k}`)).length;
      say(a, `lyrics: ${count("synced")} synced, ${count("plain")} plain, ${count("instrumental")} instrumental, ${count("missing")} missing${
        count("failed") ? `, ${count("failed")} failed (rerun lyrics)` : ""}`);
    }));
    say(a, skipped.has(a.path) ? "RYM: not on RYM" : "RYM: page grabbed");
    run(["bun", `${SCRIPTS}/resolve.ts`, a.slug]);
    const rec = JSON.parse(readFileSync(`${CATALOGUE}/${a.slug}.json`, "utf8")) as { tracks: { ids: { acoustid_agrees?: boolean | null } }[] };
    const agree = rec.tracks.map((t) => t.ids.acoustid_agrees);
    say(a, `AcoustID: ${agree.filter((x) => x === true).length} agree, ${agree.filter((x) => x === false).length} differ, ${
      agree.filter((x) => x == null).length} unknown`);
    say(a, `times: ${Object.entries(times).map(([k, v]) => `${k} ${v}s`).join(", ")}`);
    await marker({ failed: null });
    console.log(`PREPARED ${a.slug}`);
    return true;
  } catch (e) {
    say(a, `failed: ${(e as Error).message}`);
    await marker({ failed: (e as Error).message });
    console.log(`PREPARED ${a.slug} (failed)`);
    return false;
  }
}

const started = Date.now();
for (const a of albums) if (existsSync(`${RAW}/${a.slug}/prepared.json`)) Bun.spawnSync(["mv", `${RAW}/${a.slug}/prepared.json`, `${RAW}/${a.slug}/prepared.previous.json`]);
fingerprints();
const results = await Promise.all(albums.map(album));
console.log(`\nprepared ${results.filter(Boolean).length} of ${albums.length} in ${Math.round((Date.now() - started) / 1000)} s`);
