import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname } from "node:path";

import { fetchJson, mb, REL_INC } from "./lib/fetch";
import { CATALOGUE } from "./lib/paths";
import { dump, py, truthy } from "./lib/py";
import { load, save } from "./lib/raw";

type Relation = { url?: { resource: string } | null };
type Release = { "release-group": { id: string }; relations?: Relation[] };

const CHOICES = `${CATALOGUE}/editions.json`;
const args = Bun.argv.slice(2);
if (args.length !== 4) {
  console.error("usage: music:enrich <slug> <path> <release-id> <why>");
  process.exit(1);
}
const [slug, path, release, how] = args as [string, string, string, string];

const cached = load(slug, `mb_release_${release}`) as Release | null;
const rel = truthy(cached)
  ? cached!
  : save(slug, `mb_release_${release}`, await mb<Release>(`release/${release}`, { inc: REL_INC }))!;
const rgid = rel["release-group"].id;
const rgInc = "genres+tags+url-rels+artist-credits+ratings";
const rg = save(slug, `mb_rg_${rgid}`, await mb<Release>(`release-group/${rgid}`, { inc: rgInc }))!;
save(slug, `caa_release_${release}`, await fetchJson(`https://coverartarchive.org/release/${release}`, 0.5));
save(slug, `caa_rg_${rgid}`, await fetchJson(`https://coverartarchive.org/release-group/${rgid}`, 0.5));
const urls = [...(rel.relations ?? []), ...(rg.relations ?? [])].filter((r) => truthy(r.url)).map((r) => r.url!.resource);
const first = (needle: string, re: RegExp) => {
  const u = urls.find((x) => x.includes(needle));
  return u === undefined ? null : re.exec(u)![1]!;
};
const dr = first("discogs.com/release/", /release\/(\d+)/);
const dm = first("discogs.com/master/", /master\/(\d+)/);
if (dr) save(slug, `discogs_release_${dr}`, await fetchJson(`https://api.discogs.com/releases/${dr}`, 2.6));
if (dm) save(slug, `discogs_master_${dm}`, await fetchJson(`https://api.discogs.com/masters/${dm}`, 2.6));
mkdirSync(dirname(CHOICES), { recursive: true });
const ch = (existsSync(CHOICES) ? JSON.parse(readFileSync(CHOICES, "utf8")) : {}) as Record<string, unknown>;
ch[slug] = { path, release, release_group: rgid, discogs_release: dr, discogs_master: dm, how };
dump(CHOICES, ch);
console.log([slug, rgid, "discogs", py(dr), py(dm), "urls", urls.length].join(" "));
