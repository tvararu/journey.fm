const base = process.env["JELLYFIN_URL"];
if (!base) throw new Error("JELLYFIN_URL is not set");
const auth = `MediaBrowser Client="journey", Device="t1", DeviceId="journey-t1", Version="1"`;
const login = await fetch(`${base}/Users/AuthenticateByName`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: auth },
  body: JSON.stringify({ Username: process.env["JELLYFIN_USERNAME"], Pw: process.env["JELLYFIN_PASSWORD"] }),
}).then((r) => r.json());
const H = { Authorization: `${auth}, Token="${login.AccessToken}"`, "Content-Type": "application/json" };

async function call(path: string, init: RequestInit = {}): Promise<any> {
  const r = await fetch(`${base}${path}`, { ...init, headers: H });
  if (!r.ok) throw new Error(`${init.method ?? "GET"} ${path}: ${r.status} ${await r.text()}`);
  return r.status === 204 ? null : r.json();
}

type Folder = { Name: string; ItemId: string; RefreshStatus?: string; RefreshProgress?: number; LibraryOptions: Record<string, unknown> };
const music = async () => ((await call("/Library/VirtualFolders")) as Folder[]).find((f) => f.Name === "Music")!;

async function refresh(): Promise<void> {
  const lib = await music();
  await call(`/Items/${lib.ItemId}/Refresh?Recursive=true&MetadataRefreshMode=Default&ImageRefreshMode=Default&ReplaceAllMetadata=true&ReplaceAllImages=false`, { method: "POST" });
  await Bun.sleep(5000);
  for (;;) {
    const f = await music();
    if (f.RefreshStatus !== "Active") break;
    console.log(`refreshing ${Math.round(f.RefreshProgress ?? 0)}%`);
    await Bun.sleep(30000);
  }
  console.log("refreshed");
  const { Items } = await call(`/Artists/AlbumArtists?userId=${login.User.Id}&ParentId=${lib.ItemId}`);
  for (const a of Items) {
    await call(`/Items/${a.Id}/Refresh?MetadataRefreshMode=Default&ImageRefreshMode=None&ReplaceAllMetadata=false&ReplaceAllImages=false`, { method: "POST" });
  }
  console.log(`queued ${Items.length} album artists`);
}

async function clear(): Promise<void> {
  const lib = await music();
  const user = login.User.Id;
  const { Items } = await call(`/Users/${user}/Items?ParentId=${lib.ItemId}&IncludeItemTypes=MusicAlbum&Recursive=true&Fields=Overview,Tags,ProviderIds`);
  let n = 0;
  for (const a of Items) {
    const stale = Object.keys(a.ProviderIds ?? {}).filter((k) => k.startsWith("AudioDb"));
    if (!a.Overview && !a.Tags?.length && !stale.length) continue;
    const item = await call(`/Users/${user}/Items/${a.Id}`);
    item.Overview = "";
    item.Tags = [];
    for (const k of stale) delete item.ProviderIds[k];
    await call(`/Items/${a.Id}`, { method: "POST", body: JSON.stringify(item) });
    n++;
  }
  console.log(`cleared ${n} of ${Items.length} albums`);
}

const HIDE_TAGS = ".itemTags { display: none !important; }";

async function options(): Promise<void> {
  const lib = await music();
  if (lib.LibraryOptions["PreferNonstandardArtistsTag"] === true) {
    console.log("PreferNonstandardArtistsTag already on");
  } else {
    await call("/Library/VirtualFolders/LibraryOptions", {
      method: "POST",
      body: JSON.stringify({ Id: lib.ItemId, LibraryOptions: { ...lib.LibraryOptions, PreferNonstandardArtistsTag: true } }),
    });
    console.log("PreferNonstandardArtistsTag on");
  }
  const branding = await call("/System/Configuration/branding");
  const css: string = branding.CustomCss ?? "";
  if (css.includes(HIDE_TAGS)) {
    console.log("tags already hidden in the web UI");
    return;
  }
  await call("/System/Configuration/branding", {
    method: "POST",
    body: JSON.stringify({ ...branding, CustomCss: css ? `${css}\n${HIDE_TAGS}` : HIDE_TAGS }),
  });
  console.log("tags hidden in the web UI");
}

const cmd = Bun.argv[2];
if (cmd === "refresh") await refresh();
else if (cmd === "clear") await clear();
else if (cmd === "options") await options();
else {
  console.error("usage: jellyfin refresh | clear | options | test | plugin");
  process.exit(1);
}

export {};
