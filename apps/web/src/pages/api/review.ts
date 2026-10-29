import type { APIRoute } from "astro";

import { ROOT } from "@/lib/paths";
import { coverChoices, processed } from "@/lib/records";
import { addReview, fingerprint } from "@/lib/reviews";

function run(args: string[]): void {
  const p = Bun.spawnSync(["bun", ...args], { cwd: ROOT, stderr: "pipe" });
  if (p.exitCode !== 0) throw new Error(`${args[0]} failed: ${p.stderr.toString().slice(0, 400)}`);
}

export const POST: APIRoute = async ({ request, redirect, cookies }) => {
  const form = await request.formData();
  const album = String(form.get("album") ?? "");
  const message = String(form.get("message") ?? "").trim();
  const verdict = form.get("verdict") === "request_changes" ? "request_changes" : "accept";
  const back = String(form.get("back") ?? "/");
  let rec = (await processed()).get(album);
  if (!rec) return new Response("only processed albums can be reviewed", { status: 400 });
  if (verdict === "request_changes" && !message) return new Response("say what should change", { status: 400 });
  const cover = String(form.get("cover") ?? "");
  const current = (await coverChoices())[rec.slug]?.chosen.id;
  if (cover && cover !== current) {
    run(["scripts/covers.ts", "choose", rec.slug, cover, "Picked as master by deity in review", "--keep"]);
    run(["scripts/resolve.ts"]);
    rec = (await processed()).get(album) ?? rec;
  }
  const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
  await addReview({ album, at, by: "deity", cover: cover || current || "", fingerprint: fingerprint(rec), message, verdict });
  if (verdict === "accept") {
    cookies.set("flash", `Accepted ${album.split("/").slice(1).join(" - ")}`, { maxAge: 60, path: "/" });
    return redirect("/?f=review", 303);
  }
  return redirect(`${back.startsWith("/album/") ? back : "/"}#conversation`, 303);
};
