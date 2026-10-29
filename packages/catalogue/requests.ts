type Entry = { at: string; album: string; by: string; text?: string; verdict?: string; message?: string };

async function lines(name: string): Promise<Entry[]> {
  const file = Bun.file(`${import.meta.dir}/../${name}`);
  return (await file.exists()) ? (await file.text()).split("\n").filter(Boolean).map((l) => JSON.parse(l) as Entry) : [];
}

const [notes, reviews] = await Promise.all([lines("notes.jsonl"), lines("reviews.jsonl")]);
const latest = new Map<string, Entry>();
for (const r of reviews) latest.set(r.album, r);
const open = [...latest.values()].filter((r) => r.verdict === "request_changes");
if (open.length === 0) console.log("No open change requests.");
for (const r of open) {
  console.log(`${r.album}\n  ${r.at} ${r.by} requested changes: ${r.message}`);
  for (const n of notes.filter((x) => x.album === r.album && x.at > r.at)) console.log(`  ${n.at} ${n.by}: ${n.text}`);
  console.log("");
}
