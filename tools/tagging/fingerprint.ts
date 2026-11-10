import { appendFileSync, existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

type Row = { path: string; size: number; mtime: number; duration?: number; fingerprint?: string; error?: string };

const ROOT = process.env["JOURNEY_LIBRARY"] ?? "";
if (!ROOT) throw new Error("JOURNEY_LIBRARY is not set: the folder that holds Music");
const FPCALC = process.env["FPCALC"] ?? "fpcalc";
const JOBS = Number(process.env["JOBS"] ?? 4);
const [arg, ...dirs] = Bun.argv.slice(2);
if (!arg) {
  console.error("usage: fingerprint.ts <out.jsonl> [dir under the library ...]  (default: Music)");
  process.exit(1);
}

function walk(dir: string, acc: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (e.name.toLowerCase().endsWith(".flac")) acc.push(p);
  }
  return acc;
}

const out = arg;
const done = new Set<string>();
if (existsSync(out)) {
  for (const line of readFileSync(out, "utf8").split("\n").filter(Boolean)) {
    const r = JSON.parse(line) as Row;
    if (r.fingerprint) done.add(`${r.path}\t${r.size}\t${r.mtime}`);
  }
}
const files = (dirs.length ? dirs : ["Music"]).flatMap((d) => walk(join(ROOT, d))).sort();
const todo = files
  .map((p) => ({ p, s: statSync(p) }))
  .filter(({ p, s }) => !done.has(`${relative(ROOT, p)}\t${s.size}\t${Math.floor(s.mtimeMs / 1000)}`));
console.log(`${files.length} files, ${todo.length} to fingerprint`);

let n = 0;
async function worker(): Promise<void> {
  for (;;) {
    const job = todo.shift();
    if (!job) return;
    const row: Row = { path: relative(ROOT, job.p), size: job.s.size, mtime: Math.floor(job.s.mtimeMs / 1000) };
    const p = Bun.spawn([FPCALC, "-json", job.p], { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
    const [text, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
    if (code === 0) Object.assign(row, JSON.parse(text) as { duration: number; fingerprint: string });
    else row.error = err.trim().slice(0, 300) || `exit ${code}`;
    appendFileSync(out, `${JSON.stringify(row)}\n`);
    if (++n % 250 === 0) console.log(n, row.path);
  }
}
await Promise.all(Array.from({ length: JOBS }, worker));
console.log(`done, ${n} fingerprinted`);
