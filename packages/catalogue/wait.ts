import { existsSync, readFileSync } from "node:fs";

import { RAW } from "./lib/paths";

const [slug, minutes = "9"] = Bun.argv.slice(2);
if (!slug) {
  console.error("usage: music:wait <slug> [minutes]");
  process.exit(1);
}
const marker = `${RAW}/${slug}/prepared.json`;
const until = Date.now() + Number(minutes) * 60_000;
while (!existsSync(marker) && Date.now() < until) await Bun.sleep(5000);
if (!existsSync(marker)) {
  console.log(`still waiting: ${slug} is not prepared yet; run music:wait ${slug} again`);
  process.exit(2);
}
const m = JSON.parse(readFileSync(marker, "utf8")) as { failed: string | null };
console.log(m.failed ? `failed: ${m.failed}` : `ready: ${slug}`);
