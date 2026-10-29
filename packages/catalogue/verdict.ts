import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";

process.env["JOURNEY_ROOT"] ??= `${import.meta.dir}/../..`;
const { processed } = await import("../../apps/web/src/lib/records");
const { addReview, fingerprint } = await import("../../apps/web/src/lib/reviews");
const { coverChoices } = await import("../../apps/web/src/lib/records");
const { addVerdict } = await import("../../apps/web/src/lib/verdicts");
const { DATA } = await import("../../apps/web/src/lib/paths");

const usage =
  'usage: verdict <slug> approve "<message>" | verdict <slug> flag "<message>" [--question <field> --pick <value> --pick-from <sources> --other <value> --other-from <sources>]';
const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    question: { type: "string" },
    pick: { type: "string" },
    "pick-from": { type: "string" },
    other: { type: "string" },
    "other-from": { type: "string" },
  },
});
const [slug, verdict, ...rest] = positionals;
const message = rest.join(" ").trim();
const given = Object.values(values).filter((v) => v !== undefined).length;
if (
  !(slug && (verdict === "approve" || verdict === "flag") && message) ||
  (verdict === "approve" && given > 0) ||
  (verdict === "flag" && given > 0 && given < 5)
) {
  console.error(usage);
  process.exit(1);
}
const question =
  given === 5
    ? {
        field: values.question as string,
        pick: { value: values.pick as string, from: values["pick-from"] as string },
        other: { value: values.other as string, from: values["other-from"] as string },
      }
    : undefined;
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
  await addVerdict({ album, at, by: "claude", fingerprint: fingerprint(rec), message, verdict, ...(question && { question }) });
  console.log(`blocked ${album}`);
}
