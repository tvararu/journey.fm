import { typing } from "@/app/keys";

type Item = { id: number | string; title: string; artist: string; cover: string | null; state: string };

const root = document.querySelector<HTMLElement>("#album")!;
const id = root.dataset["id"]!;
const serverState = root.dataset["state"]!;
const phone = () => !matchMedia("(min-width: 1024px)").matches;

const read = (key: string): string | null => {
  try {
    return sessionStorage.getItem(key);
  } catch {
    return null;
  }
};

let queue: Item[] = [];
try {
  queue = JSON.parse(read("queue") ?? "[]") as Item[];
} catch {}
const save = () => {
  try {
    sessionStorage.setItem("queue", JSON.stringify(queue));
  } catch {}
};
const pos = queue.findIndex((q) => String(q.id) === id);
if (pos >= 0 && queue[pos]!.state !== serverState) {
  queue[pos]!.state = serverState;
  save();
}
const next = pos >= 0 ? queue[pos + 1] : undefined;
const prev = pos > 0 ? queue[pos - 1] : undefined;
const href = (q: Item) => `/album/${q.id}`;

const list = read("list");
const field = (name: string) => document.querySelector<HTMLInputElement>(`input[name=${name}]`);
if (list?.startsWith("/")) {
  const f = field("list");
  if (f) f.value = list;
  const back = document.querySelector<HTMLAnchorElement>("#phone-back");
  if (back) back.href = list;
}

if (pos >= 0) {
  const label = `${pos + 1} of ${queue.length} · ${serverState}`;
  const phoneLabel = document.querySelector("#phone-pos");
  if (phoneLabel) phoneLabel.textContent = label;
  const statusCount = document.querySelector(".status .status-text");
  if (statusCount) statusCount.textContent = label;

  const rail = document.querySelector<HTMLElement>("#queue")!;
  const items = rail.querySelector<HTMLElement>("#queue-items")!;
  queue.forEach((q, i) => {
    const a = document.createElement("a");
    a.href = href(q);
    a.title = q.title;
    a.ariaLabel = q.title;
    a.className = "relative block size-14 shrink-0 bg-dark";
    if (i < pos) a.classList.add("opacity-45");
    if (i === pos) {
      a.classList.add("border-2", "border-active");
      a.ariaCurrent = "page";
    }
    if (q.cover) {
      const img = document.createElement("img");
      img.src = q.cover;
      img.alt = "";
      img.loading = "lazy";
      img.className = "size-full object-cover";
      a.append(img);
    }
    if (q.state === "accepted") {
      const mark = document.createElement("span");
      mark.textContent = "✓";
      mark.className = "absolute bottom-0 left-0 grid size-3.5 place-items-center bg-fg text-[10px] font-extrabold text-bg";
      a.append(mark);
    }
    items.append(a);
    if (i === pos) requestAnimationFrame(() => a.scrollIntoView({ block: "center" }));
  });
  rail.querySelector("#queue-pos")!.textContent = `${pos + 1} / ${queue.length}`;
  rail.querySelector("#queue-state")!.textContent = serverState;
  rail.dataset["on"] = "";
}

if (next) {
  const f = field("next");
  if (f) f.value = href(next);
  const nextBtn = document.querySelector<HTMLElement>("#accept-next");
  if (nextBtn) nextBtn.dataset["show"] = "";
  const phoneAccept = document.querySelector<HTMLButtonElement>("#accept-phone");
  if (phoneAccept) {
    phoneAccept.value = "accept_next";
    phoneAccept.textContent = "ACCEPT, NEXT ❯";
  }
  const nextLink = document.querySelector<HTMLAnchorElement>("#next-phone");
  if (nextLink) {
    nextLink.href = href(next);
    nextLink.dataset["show"] = "";
  }
}

const buttons = [...document.querySelectorAll<HTMLElement>("[data-tab-btn]")];
const tabs = new Set(buttons.map((b) => b.dataset["tabBtn"]!));
function setTab(tab: string, store = true) {
  if (!tabs.has(tab)) return;
  root.dataset["tab"] = tab;
  for (const b of buttons) b.ariaSelected = String(b.dataset["tabBtn"] === tab);
  if (store) history.replaceState(null, "", `#${tab}`);
}
const hash = location.hash.slice(1);
const initial = hash === "log" && !phone() ? root.dataset["first"]! : hash;
if (tabs.has(initial)) setTab(initial, false);
for (const b of buttons) b.addEventListener("click", () => setTab(b.dataset["tabBtn"]!));

const message = () => document.querySelector<HTMLTextAreaElement>("#rv-msg");
function requestChanges() {
  if (phone()) setTab("log");
  message()?.focus();
}
document.addEventListener("click", (e) => {
  const target = e.target as Element;
  if (target.closest("[data-request-changes]")) {
    requestChanges();
    return;
  }
  const toggle = target.closest<HTMLElement>("[data-track-toggle]");
  if (toggle) {
    const panel = document.getElementById(toggle.getAttribute("aria-controls") ?? "");
    if (!panel) return;
    panel.hidden = !panel.hidden;
    toggle.setAttribute("aria-expanded", String(!panel.hidden));
  }
});

document.addEventListener("change", (e) => {
  const t = e.target as HTMLInputElement;
  if (t.matches?.("input[name=cover]") && t.checked) {
    const label = document.querySelector("#master-label");
    if (label && t.dataset["label"]) label.textContent = t.dataset["label"];
  }
});

document.querySelector<HTMLFormElement>("#review")?.addEventListener("submit", (e) => {
  if (pos < 0) return;
  const s = (e as SubmitEvent).submitter as HTMLButtonElement | null;
  const name = s?.name;
  const value = s?.value;
  let state: string | null = null;
  if (name === "verdict") state = value === "request_changes" ? "changes requested" : "accepted";
  if (name === "decision") state = value === "pick" ? "accepted" : "changes requested";
  if (!state) return;
  queue[pos]!.state = state;
  save();
});

const KEYS: Record<string, string> = { t: "tracks", g: "tags", c: "cover", s: "sources", f: "files" };
document.addEventListener("keydown", (e) => {
  if (typing(e) || e.defaultPrevented) return;
  const tab = KEYS[e.key];
  if (tab && tabs.has(tab)) {
    e.preventDefault();
    setTab(tab);
  } else if (e.key === "n" && next) location.href = href(next);
  else if (e.key === "p" && prev) location.href = href(prev);
  else if (e.key === "r" && message()) {
    e.preventDefault();
    requestChanges();
  } else if (e.key === "Enter") {
    if ((e.target as Element).closest("a, button, summary, input")) return;
    const accept = document.querySelector<HTMLButtonElement>("#accept-next");
    if (accept && accept.offsetParent) {
      e.preventDefault();
      accept.click();
    }
  }
});
