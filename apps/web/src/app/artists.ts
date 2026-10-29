import { typing } from "@/app/keys";

const list = document.getElementById("ar-list")!;
const input = document.getElementById("ar-q") as HTMLInputElement;
const rows = [...list.querySelectorAll<HTMLElement>("[data-row]")];
const heads = [...list.querySelectorAll<HTMLElement>("[data-head]")];

const jump = (letter: string) => list.querySelector<HTMLElement>(`[data-head="${letter}"]`)?.scrollIntoView({ block: "start" });

for (const b of document.querySelectorAll<HTMLButtonElement>("[data-letter]")) {
  b.addEventListener("click", () => jump(b.dataset.letter!));
}

list.querySelector<HTMLElement>("[aria-current]")?.scrollIntoView({ block: "center" });

input.addEventListener("input", () => {
  const q = input.value.trim().toLowerCase();
  for (const r of rows) r.hidden = !r.dataset.name!.includes(q);
  for (const h of heads) h.hidden = !rows.some((r) => r.dataset.row === h.dataset.head && !r.hidden);
});

const disc = document.getElementById("disc")!;
const segs = [...document.querySelectorAll<HTMLButtonElement>("[data-show]")];
for (const s of segs) {
  s.addEventListener("click", () => {
    for (const o of segs) o.setAttribute("aria-pressed", String(o === s));
    for (const a of disc.children as HTMLCollectionOf<HTMLElement>) {
      a.hidden = s.dataset.show !== "all" && a.dataset.state !== s.dataset.show;
    }
  });
}

const queue = document.getElementById("disc-queue")!.textContent!;
disc.addEventListener("click", (e) => {
  if (!(e.target as Element).closest("a")) return;
  sessionStorage.setItem("queue", queue);
  sessionStorage.setItem("list", location.pathname);
});

document.addEventListener("keydown", (e) => {
  if (typing(e)) return;
  if (e.key === "j" || e.key === "k") {
    const links = rows.filter((r) => !r.hidden);
    const i = links.findIndex((r) => r.hasAttribute("aria-current"));
    const to = links[e.key === "j" ? i + 1 : i - 1];
    if (to) location.href = to.getAttribute("href")!;
  } else if (/^[a-z]$/i.test(e.key)) {
    jump(e.key.toUpperCase());
  }
});
