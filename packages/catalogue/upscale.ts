import { readFileSync } from "node:fs";

process.env["CATALOGUE_DATA"] ??= `${import.meta.dir}/../data`;
const { DATA } = await import("../web/src/lib/paths");
const { addNote, coverCandidates } = await import("../web/src/lib/records");
const { UPSCALERS, upscale } = await import("../web/src/lib/upscale");
type Upscaler = keyof typeof UPSCALERS;

const [slug, id, which = "ultrasharpv2"] = Bun.argv.slice(2);
if (!(slug && id && which in UPSCALERS)) {
  console.error(`usage: music:upscale <slug> <candidate-id> [${Object.keys(UPSCALERS).join(" | ")}]`);
  process.exit(1);
}
const cands = await coverCandidates(slug);
const c = cands.find((x) => x.id === id);
if (!c) throw new Error(`no candidate ${id} for ${slug}`);
const u = UPSCALERS[which as Upscaler];
const made = await upscale(slug, c, which as Upscaler);
const path = `${DATA}/raw/${slug}/covers/candidates.json`;
const now = await coverCandidates(slug);
await Bun.write(path, JSON.stringify([...now.filter((x) => x.id !== made.id), made], null, 1));
const editions = JSON.parse(readFileSync(`${DATA}/catalogue/editions.json`, "utf8")) as Record<string, { path: string }>;
const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
const album = editions[slug]?.path ?? slug;
await addNote({ album, at, by: "claude", text: `Upscaled the ${c.source} cover (${c.width}x${c.height}) with ${u.label} to ${made.width}x${made.height}. The master is unchanged; pick it in review if it's better.` });
console.log(made.id, `${made.width}x${made.height}`);
