import { readFileSync } from "node:fs";

process.env["JOURNEY_ROOT"] ??= `${import.meta.dir}/../..`;
const { processed } = await import("../../apps/web/src/lib/records");
const { addReview, fingerprint } = await import("../../apps/web/src/lib/reviews");
const { coverChoices } = await import("../../apps/web/src/lib/records");
const { addVerdict } = await import("../../apps/web/src/lib/verdicts");
const { DATA } = await import("../../apps/web/src/lib/paths");

const [slug, verdict, ...rest] = Bun.argv.slice(2);
const message = rest.join(" ").trim();
if (!(slug && (verdict === "approve" || verdict === "flag") && message)) {
  console.error('usage: verdict <slug> approve|flag "<message>"');
  process.exit(1);
}
const editions = JSON.parse(readFileSync(`${DATA}/catalogue/editions.json`, "utf8")) as Record<string, { path: string }>;
const album = editions[slug]?.path;
const rec = album ? (await processed()).get(album) : undefined;
if (!(album && rec)) throw new Error(`no processed album for ${slug}; run resolve first`);
const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
if (verdict === "approve") {
  const cover = (await coverChoices())[slug]?.chosen.id ?? "";
  await addReview({ album, at, by: "claude", cover, fingerprint: fingerprint(rec), message, verdict: "accept" });
  console.log(`accepted ${album}`);
} else {
  await addVerdict({ album, at, by: "claude", fingerprint: fingerprint(rec), message, verdict });
  console.log(`blocked ${album}`);
}
