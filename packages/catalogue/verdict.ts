import { readFileSync } from "node:fs";

process.env["CATALOGUE_DATA"] ??= `${import.meta.dir}/../data`;
const { processed } = await import("../web/src/lib/records");
const { fingerprint } = await import("../web/src/lib/reviews");
const { addVerdict } = await import("../web/src/lib/verdicts");
const { DATA } = await import("../web/src/lib/paths");

const [slug, verdict, ...rest] = Bun.argv.slice(2);
const message = rest.join(" ").trim();
if (!(slug && (verdict === "approve" || verdict === "flag") && message)) {
  console.error('usage: music:verdict <slug> approve|flag "<message>"');
  process.exit(1);
}
const editions = JSON.parse(readFileSync(`${DATA}/catalogue/editions.json`, "utf8")) as Record<string, { path: string }>;
const album = editions[slug]?.path;
const rec = album ? (await processed()).get(album) : undefined;
if (!(album && rec)) throw new Error(`no processed album for ${slug}; run music:resolve first`);
const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
await addVerdict({ album, at, by: "claude", fingerprint: fingerprint(rec), message, verdict });
console.log(`${verdict === "approve" ? "approved" : "flagged"} ${album}`);
