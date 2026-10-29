import { typing } from "@/app/keys";

const queues = JSON.parse(document.getElementById("queues")?.textContent ?? "{}") as Record<string, unknown[]>;

document.addEventListener("click", (e) => {
  const a = (e.target as Element).closest<HTMLElement>("[data-queue]");
  if (!a) return;
  sessionStorage.setItem("queue", JSON.stringify(queues[a.dataset.queue!] ?? []));
  sessionStorage.setItem("list", "/review");
});

document.getElementById("show-all")?.addEventListener("click", (e) => {
  for (const el of document.querySelectorAll("[data-more]")) el.classList.remove("hidden");
  (e.currentTarget as HTMLElement).remove();
});

const feed = document.getElementById("feed")!;
const tabs = [...document.querySelectorAll<HTMLButtonElement>("#tabs [data-tab]")];
for (const t of tabs) {
  t.addEventListener("click", () => {
    for (const o of tabs) o.setAttribute("aria-pressed", String(o === t));
    for (const li of feed.children as HTMLCollectionOf<HTMLElement>) {
      li.hidden = t.dataset.tab !== "all" && li.dataset.kind !== t.dataset.tab;
    }
  });
}

let sel: HTMLElement | null = null;
const picks = () => [...document.querySelectorAll<HTMLElement>("[data-pick]")].filter((el) => el.offsetParent !== null);
const select = (el: HTMLElement | null) => {
  sel?.classList.remove("outline", "outline-2", "outline-active");
  sel = el;
  if (!el) return;
  el.classList.add("outline", "outline-2", "outline-active");
  el.scrollIntoView({ block: "nearest" });
};
const open = () => {
  const link = sel instanceof HTMLAnchorElement ? sel : sel?.querySelector<HTMLAnchorElement>("a[href]");
  link?.click();
};

document.addEventListener("keydown", (e) => {
  if (typing(e)) return;
  if (e.key === "j" || e.key === "k") {
    const list = picks();
    if (!list.length) return;
    const i = sel ? list.indexOf(sel) : -1;
    select(list[e.key === "j" ? Math.min(list.length - 1, i + 1) : Math.max(0, i - 1)]!);
  } else if (e.key === "o" && sel) {
    open();
  } else if (e.key === "Enter") {
    if ((e.target as Element).closest("a,button,summary,input")) return;
    if (sel) open();
    else document.getElementById("start")?.click();
  }
});
