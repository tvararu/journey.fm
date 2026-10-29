import type { APIRoute } from "astro";

import { ROOT, SCRIPTS } from "@/lib/paths";
import { coverChoices, processed } from "@/lib/records";
import { addReview, fingerprint, reviews } from "@/lib/reviews";
import { openQuestion, verdicts } from "@/lib/verdicts";

function run(args: string[]): void {
  const p = Bun.spawnSync(["bun", ...args], { cwd: ROOT, stderr: "pipe" });
  if (p.exitCode !== 0) throw new Error(`${args[0]} failed: ${p.stderr.toString().slice(0, 400)}`);
}

export const POST: APIRoute = async ({ request, redirect, cookies }) => {
  const form = await request.formData();
  const album = String(form.get("album") ?? "");
  const comment = String(form.get("message") ?? "").trim();
  const decision = String(form.get("decision") ?? "");
  const action = String(form.get("verdict") ?? "");
  const next = action === "accept_next" ? String(form.get("next") ?? "") : "";
  const back = String(form.get("back") ?? "/");
  const list = String(form.get("list") ?? "");
  let rec = (await processed()).get(album);
  if (!rec) return new Response("only processed albums can be reviewed", { status: 400 });
  let verdict: "accept" | "request_changes" = action === "request_changes" ? "request_changes" : "accept";
  let message = comment;
  if (decision === "pick" || decision === "other") {
    const q = openQuestion(rec, (await reviews()).get(album) ?? [], (await verdicts()).get(album) ?? []);
    if (!q) return new Response("no open question for this album", { status: 400 });
    const side = decision === "pick" ? q.pick : q.other;
    verdict = decision === "pick" ? "accept" : "request_changes";
    message = `${decision === "pick" ? "Kept" : "Use"} ${side.value} (${side.from}) for ${q.field}.${comment ? `\n\n${comment}` : ""}`;
  } else if (verdict === "request_changes" && !message) {
    return new Response("say what should change", { status: 400 });
  }
  const cover = String(form.get("cover") ?? "");
  const current = (await coverChoices())[rec.slug]?.chosen.id;
  if (cover && cover !== current) {
    run([`${SCRIPTS}/covers.ts`, "choose", rec.slug, cover, "Picked as master by deity in review", "--keep"]);
    run([`${SCRIPTS}/resolve.ts`]);
    rec = (await processed()).get(album) ?? rec;
  }
  const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
  await addReview({ album, at, by: "deity", cover: cover || current || "", fingerprint: fingerprint(rec), message, verdict });
  const name = album.split("/").slice(1).join(" - ");
  if (verdict === "accept") {
    cookies.set("flash", `Accepted ${name}`, { maxAge: 60, path: "/" });
    if (/^\/album\/\d+$/.test(next)) return redirect(next, 303);
    return redirect(/^\/(review)?(\?|$)/.test(list) ? list : "/", 303);
  }
  cookies.set("flash", `Requested changes on ${name}`, { maxAge: 60, path: "/" });
  if (back === "/review") return redirect("/review", 303);
  return redirect(back.startsWith("/album/") ? `${back.split("#")[0]}#log` : "/", 303);
};
