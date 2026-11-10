import { createSign } from "node:crypto";

const [build] = process.argv.slice(2);
if (!build) throw new Error("usage: bun testflight.ts <build number>");

function token() {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: process.env.ASC_KEY_ID, typ: "JWT" })}.${encode({
    iss: process.env.ASC_ISSUER_ID,
    iat: now,
    exp: now + 600,
    aud: "appstoreconnect-v1",
  })}`;
  const signature = createSign("SHA256")
    .update(unsigned)
    .sign({ key: Buffer.from(process.env.ASC_KEY_P8!, "base64").toString(), dsaEncoding: "ieee-p1363" })
    .toString("base64url");
  return `${unsigned}.${signature}`;
}

async function get(path: string) {
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1/${path}`, {
    headers: { Authorization: `Bearer ${token()}` },
  });
  if (!response.ok) throw new Error(`App Store Connect answered ${response.status} for ${path.split("?")[0]}`);
  return (await response.json()).data;
}

const bundle = /^PRODUCT_BUNDLE_IDENTIFIER *= *(\S+)/m.exec(await Bun.file(`${import.meta.dir}/Local.xcconfig`).text())?.[1];
if (!bundle) throw new Error("Local.xcconfig has no PRODUCT_BUNDLE_IDENTIFIER");
const [app] = await get(`apps?filter[bundleId]=${bundle}&fields[apps]=bundleId`);
const deadline = Date.now() + 45 * 60 * 1000;
let last = "";
while (Date.now() < deadline) {
  const [found] = await get(`builds?filter[app]=${app.id}&filter[version]=${build}&fields[builds]=processingState`);
  const state = found?.attributes.processingState ?? "NOT YET LISTED";
  if (state !== last) console.log(`Build ${build}: ${state}`);
  last = state;
  if (state === "VALID") process.exit(0);
  if (state === "FAILED" || state === "INVALID") process.exit(1);
  await Bun.sleep(30_000);
}
console.error(`Build ${build} still ${last} after 45 minutes`);
process.exit(1);
