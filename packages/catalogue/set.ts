import { appendFileSync, existsSync, readFileSync } from "node:fs";

import { OVERRIDES, type Override } from "./lib/overrides";
import { CATALOGUE } from "./lib/paths";

const args = Bun.argv.slice(2);
const flag = (name: string, fallback: string) => {
  const at = args.indexOf(name);
  return at >= 0 ? (args.splice(at, 2)[1] ?? fallback) : fallback;
};
const by = flag("--by", "claude");
const why = flag("--why", "");
const clear = args.includes("--clear");
if (clear) args.splice(args.indexOf("--clear"), 1);
const [slug, name, ...values] = args;
if (!(slug && name && (clear || values.length))) {
  console.error('usage: set <slug> <field> <value>... [--by deity] [--why "<reason>"] | set <slug> <field> --clear');
  process.exit(1);
}
const p = `${CATALOGUE}/${slug}.json`;
if (!existsSync(p)) {
  console.error(`no catalogue record for ${slug}; prepare it first`);
  process.exit(1);
}
const rec = JSON.parse(readFileSync(p, "utf8")) as { path: string; album: Record<string, { value?: unknown } | null> };
const current = rec.album[name];
if (!current || !("value" in current)) {
  const names = Object.entries(rec.album).filter(([, f]) => f && "value" in f).map(([k]) => k);
  console.error(`no album field "${name}"; fields: ${names.join(", ")}`);
  process.exit(1);
}
if (typeof current.value === "string" && values.length > 1) {
  console.error(`${name} takes one value; quote it if it has spaces`);
  process.exit(1);
}
const value = clear ? null : Array.isArray(current.value) || values.length > 1 ? values : values[0]!;
const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
appendFileSync(OVERRIDES, `${JSON.stringify({ album: rec.path, at, by, field: name, value, why } satisfies Override)}\n`);
const r = Bun.spawnSync(["bun", `${import.meta.dir}/resolve.ts`, slug], { stdout: "ignore", stderr: "pipe" });
if (r.exitCode !== 0) throw new Error(`resolve failed: ${r.stderr.toString().slice(-400)}`);
console.log(`${rec.path}: ${name} ${clear ? "back to the sources" : `= ${JSON.stringify(value)} (${by})`}`);
