import { mins, size, stamp, when } from "../lib/format";
import { GLYPH, type Item, SECTION_NOTE, SECTION_ORDER, STATES, type State, VERB } from "../lib/state";
import { typing } from "./keys";

export type Filter = { st: string; issue: string; audio: string; decade: string; genre: string; q: string };
export type Sort = "recent" | "artist" | "year" | "size";

export const SORTS: Record<Sort, string> = {
  recent: "recent activity",
  artist: "artist",
  year: "year",
  size: "size",
};

export const PAGE = 40;

export const isFiltering = (f: Filter): boolean => !!(f.st || f.issue || f.audio || f.decade || f.genre || f.q.trim());

const decadeOf = (y: number): number => Math.floor(y / 10) * 10;

export function filterItems(items: Item[], f: Filter): Item[] {
  const tokens = f.q.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return items.filter((i) => {
    if (f.st && i.state !== f.st) return false;
    if (f.issue === "any" ? !i.issues.length : f.issue && !i.issues.includes(f.issue)) return false;
    if (f.audio && i.audio !== f.audio) return false;
    if (f.decade && (i.year === null || decadeOf(i.year) !== Number(f.decade))) return false;
    if (f.genre && i.genre !== f.genre) return false;
    if (tokens.length) {
      const hay = `${i.artist} ${i.title} ${i.path} ${i.issues.join(" ")}`.toLowerCase();
      if (!tokens.every((t) => hay.includes(t))) return false;
    }
    return true;
  });
}

const stamped = (at: string | null): string => (at ?? "").replace(" ", "T");

export function sortItems(items: Item[], sort: Sort, filtering: boolean): Item[] {
  const rank = new Map(SECTION_ORDER.map((s, i) => [s, i]));
  const recent = (a: Item, b: Item) => stamped(b.at).localeCompare(stamped(a.at)) || a.path.localeCompare(b.path);
  const year = (a: Item, b: Item) => (a.year ?? 1e9) - (b.year ?? 1e9);
  const out = items.slice();
  if (sort === "artist") return out.sort((a, b) => a.artist.localeCompare(b.artist) || year(a, b));
  if (sort === "year") return out.sort((a, b) => year(a, b) || a.artist.localeCompare(b.artist));
  if (sort === "size") return out.sort((a, b) => b.bytes - a.bytes);
  if (filtering) return out.sort(recent);
  return out.sort(
    (a, b) =>
      rank.get(a.state)! - rank.get(b.state)! ||
      (a.state === "triage" ? a.path.localeCompare(b.path) : recent(a, b)),
  );
}

export type Facets = {
  states: Record<State, number>;
  withIssues: number;
  issues: [string, number][];
  audios: [string, number][];
  codecs: string;
  decades: { d: number; n: number }[];
  genres: [string, number][];
  catalogued: number;
};

const tally = (xs: string[]): [string, number][] => {
  const m = new Map<string, number>();
  for (const x of xs) m.set(x, (m.get(x) ?? 0) + 1);
  return [...m].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
};

export function facets(items: Item[]): Facets {
  const states = Object.fromEntries(STATES.map((s) => [s, 0])) as Record<State, number>;
  for (const i of items) states[i.state]++;
  const years = items.flatMap((i) => (i.year === null ? [] : [decadeOf(i.year)]));
  const byDecade = new Map(tally(years.map(String)).map(([d, n]) => [Number(d), n]));
  const decades: { d: number; n: number }[] = [];
  if (years.length) {
    for (let d = Math.min(...years); d <= Math.max(...years); d += 10) decades.push({ d, n: byDecade.get(d) ?? 0 });
  }
  return {
    states,
    withIssues: items.filter((i) => i.issues.length).length,
    issues: tally(items.flatMap((i) => i.issues)),
    audios: tally(items.map((i) => i.audio)),
    codecs: [...new Set(items.map((i) => i.codec.toUpperCase()))].sort().join(" / "),
    decades,
    genres: tally(items.flatMap((i) => (i.genre ? [i.genre] : []))),
    catalogued: items.length - states.triage,
  };
}

const esc = (s: string): string =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

type View = Filter & { sort: Sort; view: string; sel: number; limit: number; moreGenres: boolean };

function boot(): void {
  const el = <T extends HTMLElement>(sel: string): T => document.querySelector<T>(sel)!;
  const items = JSON.parse(el("#items").textContent ?? "[]") as Item[];
  const fx = facets(items);
  const wide = matchMedia("(min-width: 1024px)");
  const mainPane = el("main[aria-label=Library]");
  const filterPane = el("nav[aria-label=Filter]");
  const infoWrap = el("#info-wrap");
  const input = el<HTMLInputElement>("#q");

  const v: View = {
    st: "", issue: "", audio: "", decade: "", genre: "", q: "",
    sort: "recent", view: "", sel: 0, limit: PAGE, moreGenres: false,
  };

  const params = new URLSearchParams(location.search);
  const st = params.get("st") ?? "";
  if ((STATES as string[]).includes(st)) v.st = st;
  v.issue = params.get("issue") ?? "";
  v.audio = params.get("audio") ?? "";
  v.decade = /^\d+$/.test(params.get("decade") ?? "") ? params.get("decade")! : "";
  v.genre = params.get("genre") ?? "";
  v.q = params.get("q") ?? "";
  const sort = params.get("sort") ?? "";
  if (sort in SORTS) v.sort = sort as Sort;
  const view = params.get("view") ?? "";
  if (view === "grid" || view === "list") v.view = view;
  v.sel = Number(params.get("sel")) || 0;
  input.value = v.q;

  const mode = (): string => v.view || (wide.matches ? "grid" : "list");

  const writeUrl = (): void => {
    const p = new URLSearchParams();
    for (const k of ["st", "issue", "audio", "decade", "genre", "q"] as const) if (v[k]) p.set(k, v[k]);
    if (v.sort !== "recent") p.set("sort", v.sort);
    if (v.view) p.set("view", v.view);
    if (v.sel) p.set("sel", String(v.sel));
    const qs = p.toString();
    history.replaceState(null, "", location.pathname + (qs ? `?${qs}` : ""));
  };

  const chipList = (): { key: keyof Filter; label: string }[] => {
    const out: { key: keyof Filter; label: string }[] = [];
    if (v.st) out.push({ key: "st", label: `state: ${v.st}` });
    if (v.issue) out.push({ key: "issue", label: v.issue === "any" ? "any issue" : v.issue });
    if (v.audio) out.push({ key: "audio", label: `audio: ${v.audio}` });
    if (v.decade) out.push({ key: "decade", label: `${v.decade}s` });
    if (v.genre) out.push({ key: "genre", label: v.genre });
    return out;
  };

  const head = (label: string, note: string, first = false): string =>
    `<div class="rule-head h-[22px] shrink-0 px-2 ${first ? "" : "mt-3"}"><span>──</span><b class="font-bold">${esc(label)}</b><span class="flex-1"></span><span>${esc(note)}</span></div>`;

  const facetRow = (act: string, val: string, glyph: string, label: string, count: number, on: boolean, danger = false): string =>
    `<button type="button" data-act="${act}" data-v="${esc(val)}" aria-pressed="${on}" class="flex h-[22px] w-full shrink-0 items-center gap-2 px-2 text-left aria-pressed:bg-sel aria-pressed:font-extrabold ${count === 0 ? "text-muted" : ""}"><span class="w-3 shrink-0 text-center ${danger ? "text-danger" : "text-muted aria-pressed:text-fg"}">${glyph}</span><span class="min-w-0 flex-1 truncate">${esc(label)}</span><span class="text-muted ${on ? "text-sel-muted" : ""}">${count}</span></button>`;

  const renderFacets = (): void => {
    const box = el("#facets");
    const top = box.scrollTop;
    const parts: string[] = [head("state", "", true)];
    parts.push(facetRow("st", "", "", "all", items.length, !v.st));
    for (const s of STATES) {
      parts.push(facetRow("st", s, GLYPH[s], s, fx.states[s], v.st === s, s === "blocked" && fx.states[s] > 0));
    }
    parts.push(head("issues", `${fx.withIssues} albums`));
    parts.push(facetRow("issue", "any", "!", "any issue", fx.withIssues, v.issue === "any", true));
    for (const [k, n] of fx.issues) parts.push(facetRow("issue", k, "!", k, n, v.issue === k, true));
    parts.push(head("audio", fx.codecs));
    for (const [k, n] of fx.audios) parts.push(facetRow("audio", k, "", k, n, v.audio === k));
    parts.push(head("decade", v.decade ? `${v.decade}s` : "year"));
    const max = Math.max(1, ...fx.decades.map((d) => d.n));
    parts.push(
      `<div class="grid h-[86px] shrink-0 items-end gap-1 px-2 pt-1.5" style="grid-template-columns:repeat(${Math.max(1, fx.decades.length)},minmax(0,1fr))">${fx.decades
        .map(({ d, n }) => {
          const on = v.decade === String(d);
          const bar = on ? "bg-fg" : v.decade ? "bg-f18" : "bg-muted";
          return `<button type="button" data-act="decade" data-v="${d}" aria-pressed="${on}" aria-label="${d}s, ${n} albums" class="flex h-full min-w-0 flex-col justify-end gap-1"><span class="block ${bar}" style="height:${Math.max(2, Math.round((n / max) * 44))}px"></span><span class="flex flex-col items-center text-[11px] leading-[1.25]"><span class="${on ? "font-extrabold" : ""}">${String(d).slice(2)}s</span><span class="text-muted">${n}</span></span></button>`;
        })
        .join("")}</div>`,
    );
    parts.push(head("genre", `${fx.catalogued} catalogued`));
    const genres = v.moreGenres ? fx.genres : fx.genres.slice(0, 8);
    parts.push(
      `<div class="flex shrink-0 flex-wrap gap-0.5 px-1 pt-1 text-[11px]">${genres
        .map(
          ([g, n]) =>
            `<button type="button" data-act="genre" data-v="${esc(g)}" aria-pressed="${v.genre === g}" class="px-[7px] py-px whitespace-nowrap aria-pressed:bg-f18 aria-pressed:font-bold">${esc(g)} <span class="text-muted">${n}</span></button>`,
        )
        .join("")}${fx.genres.length > 8 ? `<button type="button" data-act="genres" class="px-[7px] py-px text-muted">${v.moreGenres ? "fewer" : `+${fx.genres.length - 8} more`}</button>` : ""}</div>`,
    );
    box.innerHTML = parts.join("");
    box.scrollTop = top;
  };

  const thumb = (i: Item, cls: string): string =>
    i.cover
      ? `<img src="${esc(i.cover)}" alt="" loading="lazy" class="block object-cover ${cls}">`
      : `<span class="block bg-dark ${cls}"></span>`;

  const sectionHead = (s: State, n: number, first: boolean, list: boolean): string =>
    `<div class="rule-head ${list ? `px-2 pb-1.5 ${first ? "pt-2.5" : "pt-5"}` : `col-span-full ${first ? "" : "mt-2.5"}`}"><span>──</span><b class="font-extrabold text-fg">${s} · ${n}</b><span>${SECTION_NOTE[s]}</span><i class="h-px flex-1 bg-faint"></i></div>`;

  const tile = (i: Item): string => {
    const iss = i.issues.length;
    return `<a href="/album/${i.id}" data-id="${i.id}" ${i.id === v.sel ? "data-sel" : ""} class="group flex min-w-0 flex-col gap-1.5"><span class="relative block aspect-square w-full border-2 border-transparent group-data-[sel]:border-active max-lg:border-0">${thumb(i, "size-full")}${i.state === "accepted" ? `<span class="absolute bottom-1.5 left-1.5 flex size-4 items-center justify-center bg-fg text-[11px] leading-none font-extrabold text-bg">✓</span>` : ""}${iss ? `<span class="absolute right-1.5 bottom-1.5 flex h-4 items-center bg-danger px-1 text-[11px] leading-none font-extrabold text-bg">!${iss}</span>` : ""}</span><span class="flex min-w-0 flex-col gap-px px-1 py-0.5 max-lg:px-0 group-data-[sel]:bg-sel max-lg:group-data-[sel]:bg-transparent"><span class="truncate font-bold">${esc(i.title)}</span><span class="truncate text-[11px] text-muted group-data-[sel]:text-sel-muted max-lg:group-data-[sel]:text-muted">${esc(i.artist)} · ${i.year ?? "—"}</span></span></a>`;
  };

  const row = (i: Item): string => {
    const at = i.at ? when(i.at) : "—";
    const stCls = i.state === "accepted" ? "font-bold" : i.state === "blocked" ? "font-bold text-danger" : i.state === "triage" ? "text-muted" : "";
    const sub = i.by && i.at ? `${i.by} · ${at}` : "";
    return `<a href="/album/${i.id}" data-id="${i.id}" class="flex min-h-11 items-center gap-3 border-b border-f8 px-2 py-1 lg:grid lg:grid-cols-[32px_minmax(0,2.4fr)_84px_132px_44px_64px_64px_72px_minmax(0,1.4fr)_56px]">${thumb(i, "size-11 shrink-0 lg:size-8")}<span class="flex min-w-0 flex-1 flex-col lg:flex-none"><span class="truncate font-bold max-lg:text-[13px]">${esc(i.title)}</span><span class="truncate text-[11px] text-muted"><span class="lg:hidden">${esc(i.artist)} · ${esc(i.issues[0] ?? String(i.year ?? "—"))}</span><span class="max-lg:hidden">${esc(i.artist)}</span></span></span><span class="whitespace-nowrap text-fg2 max-lg:hidden">${esc(i.dateTag || "—")}</span><span class="flex min-w-0 flex-col whitespace-nowrap max-lg:hidden"><span class="${stCls}">${GLYPH[i.state]} ${i.state}</span><span class="text-[11px] text-muted">${esc(sub)}</span></span><span class="text-right max-lg:hidden">${i.n}</span><span class="whitespace-nowrap text-right text-fg2 max-lg:hidden">${mins(i.dur)}</span><span class="whitespace-nowrap text-right text-fg2 max-lg:hidden">${size(i.bytes)}</span><span class="whitespace-nowrap max-lg:hidden ${i.audio === "16/44.1" ? "text-muted" : "font-bold"}">${esc(i.audio)}</span><span class="min-w-0 truncate text-[11px] text-danger max-lg:hidden">${esc(i.issues.join(" · "))}</span><span class="text-right text-muted max-lg:hidden">${at}</span><span class="flex flex-col items-end gap-px whitespace-nowrap lg:hidden"><span class="${i.state === "blocked" ? "text-danger" : ""}">${GLYPH[i.state]}</span><span class="text-[11px] text-muted">${at}</span></span></a>`;
  };

  const renderResults = (list: Item[], filtering: boolean): void => {
    const shown = list.slice(0, v.limit);
    const sections = v.sort === "recent" && !filtering;
    const total = (s: State): number => fx.states[s];
    for (const [id, build, isList] of [["#grid", tile, false], ["#list-rows", row, true]] as const) {
      let out = "";
      let last: State | null = null;
      for (const i of shown) {
        if (sections && i.state !== last) out += sectionHead(i.state, total(i.state), last === null, isList);
        last = i.state;
        out += build(i);
      }
      el(id).innerHTML = out;
    }
    const m = mode();
    el("#grid").hidden = m !== "grid";
    el("#list").hidden = m !== "list";
    const empty = el("#empty");
    empty.hidden = list.length > 0;
    if (!list.length) {
      const onlyBlocked = v.st === "blocked" && chipList().length === 1 && !v.q.trim();
      empty.innerHTML = onlyBlocked
        ? `<span class="font-extrabold text-fg">nothing blocked</span><span>claude flags an album here when it cannot decide; it is the only queue that needs you</span>`
        : "nothing matches · clear a filter or the search";
    }
    const left = Math.max(0, list.length - v.limit);
    const more = el("#more");
    more.hidden = left === 0;
    more.textContent = `show ${PAGE} more · ${left} left`;
  };

  const phoneChips = (): string => {
    const defs: [string, number, boolean][] = [
      ["all", items.length, !v.st && !v.issue],
      ["triage", fx.states.triage, v.st === "triage"],
      ["accepted", fx.states.accepted, v.st === "accepted"],
      ["issues", fx.withIssues, v.issue === "any"],
      ["blocked", fx.states.blocked, v.st === "blocked"],
    ];
    return defs
      .map(
        ([k, n, on]) =>
          `<button type="button" data-act="phone" data-v="${k}" aria-pressed="${on}" class="h-11 shrink-0 px-0.5"><span class="flex h-[30px] items-center gap-1 border border-f18 px-2.5 ${on ? "border-transparent bg-f18 font-bold" : ""}">${k} <span class="${on ? "text-fg2" : "text-muted"}">${n}</span></span></button>`,
      )
      .join("");
  };

  const fact = (k: string, val: string | null, cls = ""): string =>
    `<div class="leader"><span class="shrink-0 text-muted">${k}</span><i></i><span class="${cls}">${esc(val ?? "—")}</span></div>`;

  const renderInfo = (): void => {
    const note = el("aside[aria-label=Info] .pane-note");
    const i = items.find((x) => x.id === v.sel);
    const box = el("#info");
    if (!i) {
      note.textContent = "";
      box.innerHTML = "";
      return;
    }
    note.textContent = `#${i.id}`;
    const cat = i.state !== "triage";
    const badge =
      i.state === "accepted" ? `<span class="badge-accepted">✓ ACCEPTED</span>`
      : i.state === "blocked" ? `<span class="badge-blocked">■ BLOCKED</span>`
      : `<span class="badge-open">${GLYPH[i.state]} ${i.state.toUpperCase()}</span>`;
    const badgeNote = !cat
      ? "not catalogued yet"
      : `${i.by ? `by ${i.by}` : "prepared"} · ${i.at ? stamp(i.at) : "—"} · ${i.entries} entries`;
    const audio = `${i.codec.toUpperCase()} ${i.audio}`;
    const facts = cat
      ? [
          fact("original", i.original), fact("edition", i.edition), fact("tracks", `${i.n} · ${mins(i.dur)}`),
          fact("audio", audio), fact("size", size(i.bytes)), fact("label", i.label), fact("genre", i.genre),
          fact("path", i.path),
        ]
      : [
          fact("date tag", i.dateTag || null), fact("tracks", `${i.n} · ${mins(i.dur)}`), fact("audio", audio),
          fact("size", size(i.bytes)), fact("path", i.path),
          fact("issues", i.issues.length ? i.issues.join(", ") : "none", i.issues.length ? "text-danger" : ""),
        ];
    const w = i.word;
    box.innerHTML = `${thumb(i, "aspect-square w-full shrink-0")}<div class="flex flex-col gap-1"><span class="text-[17px] leading-[1.2] font-extrabold text-balance">${esc(i.title)}</span><a href="/artists/${encodeURIComponent(i.artistDir)}" class="text-fg2">${esc(i.artist)}</a></div><div class="flex flex-wrap items-center gap-2">${badge}<span class="text-muted">${esc(badgeNote)}</span></div><div class="flex flex-col gap-[3px]">${facts.join("")}</div>${w ? `<div class="box gap-2"><span class="box-label"><b class="font-extrabold">${esc(w.by)}</b><span class="text-muted"> · ${VERB[w.kind]} · ${stamp(w.at)}</span></span><p class="line-clamp-8 leading-[1.55] text-fg2">${esc(w.text)}</p></div>` : ""}<span class="flex-1"></span><div class="flex flex-wrap gap-1.5"><a href="/album/${i.id}" class="btn">OPEN ALBUM ↵</a><button type="button" class="btn-2" data-copy="${esc(i.path)}">copy path</button></div>`;
  };

  const paintSel = (): void => {
    for (const a of document.querySelectorAll<HTMLElement>("#grid a[data-id]")) {
      a.toggleAttribute("data-sel", Number(a.dataset["id"]) === v.sel);
    }
    renderInfo();
    writeUrl();
  };

  const render = (): void => {
    const filtering = isFiltering(v);
    const list = sortItems(filterItems(items, v), v.sort, filtering);
    if (!list.some((i) => i.id === v.sel)) v.sel = list[0]?.id ?? 0;
    const chips = chipList();
    renderFacets();
    el("#phone-chips").innerHTML = phoneChips();
    el("#chips").innerHTML = chips
      .map(
        (c) =>
          `<button type="button" data-act="clear" data-v="${c.key}" aria-label="clear ${esc(c.label)}" class="flex h-[22px] items-center gap-1.5 bg-f18 px-2 whitespace-nowrap"><span>${esc(c.label)}</span><span class="text-muted">✕</span></button>`,
      )
      .join("");
    el("#shown").textContent = filtering ? `${list.length} match` : `${items.length} albums`;
    el("#sort-label").textContent = SORTS[v.sort];
    const m = mode();
    for (const b of document.querySelectorAll<HTMLElement>("[data-act=view]")) b.setAttribute("aria-pressed", String(b.dataset["v"] === m));
    infoWrap.hidden = m !== "grid";
    filterPane.querySelector(".pane-note")!.textContent = chips.length ? `${chips.length} on` : "all";
    mainPane.querySelector(":scope > .pane-note")!.textContent = filtering
      ? `${list.length} of ${items.length}`
      : el("#total-note").textContent;
    const status = mainPane.querySelector(".status")?.children;
    if (status) {
      status[1]!.textContent = `${list.length} albums`;
      status[3]!.textContent = `${SORTS[v.sort]} · ${chips.length ? chips.map((c) => c.label).join(" · ") : "everything"}`;
    }
    renderResults(list, filtering);
    renderInfo();
    writeUrl();
    sessionStorage.setItem("list", location.pathname + location.search);
    sessionStorage.setItem(
      "queue",
      JSON.stringify(list.map((i) => ({ id: i.id, title: i.title, artist: i.artist, cover: i.cover, state: i.state }))),
    );
  };

  const set = (patch: Partial<View>): void => {
    Object.assign(v, { limit: PAGE }, patch);
    render();
  };

  const toggle = (key: keyof Filter, val: string): void => set({ [key]: v[key] === val ? "" : val } as Partial<View>);

  document.addEventListener("click", (e) => {
    const t = (e.target as HTMLElement).closest<HTMLElement>("[data-act], [data-copy], #grid a[data-id]");
    if (!t) return;
    const val = t.dataset["v"] ?? "";
    if (t.dataset["copy"]) {
      void navigator.clipboard.writeText(t.dataset["copy"]);
      t.textContent = "copied";
      setTimeout(() => (t.textContent = "copy path"), 1500);
      return;
    }
    switch (t.dataset["act"]) {
      case "st": return set({ st: val });
      case "issue": case "audio": case "decade": case "genre": return toggle(t.dataset["act"] as keyof Filter, val);
      case "genres": return set({ moreGenres: !v.moreGenres, limit: v.limit });
      case "clear": return set({ [val]: "" } as Partial<View>);
      case "phone": return set({ st: val === "all" || val === "issues" ? "" : val, issue: val === "issues" ? "any" : "" });
      case "sort": {
        const keys = Object.keys(SORTS) as Sort[];
        return set({ sort: keys[(keys.indexOf(v.sort) + 1) % keys.length]! });
      }
      case "view": return set({ view: val, limit: v.limit });
      case "more": v.limit += PAGE; return render();
    }
    if (t.matches("#grid a[data-id]") && wide.matches && e.detail > 0) {
      e.preventDefault();
      v.sel = Number(t.dataset["id"]);
      paintSel();
    }
  });

  document.addEventListener("dblclick", (e) => {
    const t = (e.target as HTMLElement).closest<HTMLAnchorElement>("#grid a[data-id]");
    if (t) location.href = t.href;
  });

  input.addEventListener("input", () => set({ q: input.value }));
  wide.addEventListener("change", render);

  document.addEventListener("keydown", (e) => {
    if (typing(e)) return;
    if (e.key === "g") set({ view: "grid", limit: v.limit });
    else if (e.key === "l") set({ view: "list", limit: v.limit });
    else if (e.key === "Escape") {
      input.value = "";
      set({ st: "", issue: "", audio: "", decade: "", genre: "", q: "" });
    } else if (e.key === "Enter" && e.target === document.body && v.sel) location.href = `/album/${v.sel}`;
  });

  render();
}

if (typeof document !== "undefined" && document.getElementById("items")) boot();
