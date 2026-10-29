import { GLYPH, type State } from "@/lib/state";

type Data = {
  albums: { id: string; title: string; artist: string; state: State }[];
  artists: { name: string; n: number }[];
};
type Row = { href: string; glyph: string; title: string; sub: string };

const dialog = document.querySelector<HTMLDialogElement>("#palette");
const input = document.querySelector<HTMLInputElement>("#palette-input");
const list = document.querySelector<HTMLOListElement>("#palette-results");

const PAGES: Row[] = [
  { href: "/", glyph: "1", title: "library", sub: "" },
  { href: "/review", glyph: "2", title: "review", sub: "" },
  { href: "/artists", glyph: "3", title: "artists", sub: "" },
];

let data: Data | null = null;
let loading: Promise<void> | null = null;
let rows: Row[] = [];
let at = 0;

function load(): Promise<void> {
  loading ??= fetch("/api/palette")
    .then((r) => r.json() as Promise<Data>)
    .then((d) => {
      data = d;
      render();
    });
  return loading;
}

function matches(): Row[] {
  const tokens = (input?.value ?? "").toLowerCase().split(/\s+/).filter(Boolean);
  const hit = (s: string) => tokens.every((t) => s.includes(t));
  const out: Row[] = PAGES.filter((p) => hit(p.title));
  if (!data) return out;
  const albums = data.albums
    .filter((a) => hit(`${a.title} ${a.artist}`.toLowerCase()))
    .map((a): Row => ({ href: `/album/${a.id}`, glyph: GLYPH[a.state], title: a.title, sub: a.artist }));
  const artists = data.artists
    .filter((a) => hit(a.name.toLowerCase()))
    .map((a): Row => ({ href: `/artists/${encodeURIComponent(a.name)}`, glyph: "◆", title: `artist · ${a.name}`, sub: `${a.n} albums` }));
  return [...out, ...[...albums, ...artists].slice(0, 12)];
}

function render(): void {
  if (!list) return;
  rows = matches();
  at = Math.min(at, Math.max(rows.length - 1, 0));
  list.replaceChildren(
    ...rows.map((r, i) => {
      const li = document.createElement("li");
      li.className = `flex gap-2 px-2 h-7 items-center cursor-pointer ${i === at ? "bg-sel" : ""}`;
      const g = document.createElement("span");
      g.className = "w-4 text-center";
      g.textContent = r.glyph;
      const t = document.createElement("b");
      t.className = "truncate";
      t.textContent = r.title;
      const s = document.createElement("span");
      s.className = "text-muted truncate";
      s.textContent = r.sub;
      li.append(g, t, s);
      li.addEventListener("click", () => go(r));
      return li;
    }),
  );
  list.children[at]?.scrollIntoView({ block: "nearest" });
}

function go(r: Row): void {
  dialog?.close();
  location.href = r.href;
}

function open(): void {
  if (!dialog || dialog.open) return;
  if (input) input.value = "";
  at = 0;
  dialog.showModal();
  render();
  input?.focus();
  void load();
}

document.addEventListener("palette:open", open);
document.querySelectorAll("[data-palette]").forEach((b) => b.addEventListener("click", open));
input?.addEventListener("input", () => {
  at = 0;
  render();
});
input?.addEventListener("keydown", (e) => {
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    at = Math.max(0, Math.min(rows.length - 1, at + (e.key === "ArrowDown" ? 1 : -1)));
    render();
  } else if (e.key === "Enter") {
    e.preventDefault();
    const r = rows[at];
    if (r) go(r);
  }
});
