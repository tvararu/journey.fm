import { Database } from "bun:sqlite";

const [exportPath, libraryPath, outDir] = Bun.argv.slice(2);
if (!exportPath || !libraryPath || !outDir) {
  console.error("compare.ts <export.json> <library.sqlite> <out dir>");
  process.exit(1);
}

type Apple = {
  persistentID: string; name: string; artist: string; albumArtist: string;
  album: string; year: number; trackNumber: number; discNumber: number;
  duration: number; playedCount: number; playedDate: string | null;
  skippedCount: number; skippedDate: string | null; favorited: boolean;
  disliked: boolean; albumFavorited: boolean; dateAdded: string;
  cloudStatus: string; mediaKind: string; compilation: boolean;
};
type Album = { id: string; name: string; artistName: string; year: number | null };
type Track = {
  id: string; albumId: string; name: string; artistName: string;
  disc: number | null; number: number | null; duration: number;
};

const words =
  "deluxe|remaster(?:ed)?|edition|version|expanded|anniversary|bonus|explicit|clean|reissue|mono|stereo|re-armed|redux|complete|soundtrack|score|motion picture";
const edition = new RegExp(`\\s*[([][^)\\]]*\\b(?:${words})\\b[^)\\]]*[)\\]]`, "gi");
const dashed = new RegExp(`\\s+-\\s+[^-]*\\b(?:${words})\\b.*$`, "i");

function norm(text: string) {
  return text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/я/g, "r")
    .replace(/['’]/g, "")
    .replace(/[&+]/g, " and ")
    .replace(/\s+-\s+(?:ep|single)$/, "")
    .replace(/\s+ep$/, "")
    .replace(edition, "")
    .replace(dashed, "")
    .replace(/^the\s+/, "")
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

function similar(a: string, b: string) {
  if (a.includes(b) || b.includes(a)) return true;
  return distance(a, b) / Math.max(a.length, b.length) < 0.3;
}

function distance(a: string, b: string) {
  const row = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let previous = row[0];
    row[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const current = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] === b[j - 1] ? 0 : 1));
      previous = current;
    }
  }
  return row[b.length];
}

function title(text: string) {
  return norm(text.replace(/\s*[([](?:feat|ft|with)\.?\s[^)\]]*[)\]]/gi, ""));
}

const exported = await Bun.file(exportPath).json();
const apple: Apple[] = exported.tracks;
const db = new Database(libraryPath, { readonly: true });
const albums = db.query("SELECT id, name, artistName, year FROM album").all() as Album[];
const tracks = db
  .query("SELECT id, albumId, name, artistName, disc, number, duration FROM track")
  .all() as Track[];

const albumByKey = new Map<string, Album>();
const albumsByName = new Map<string, Album[]>();
for (const album of albums) {
  albumByKey.set(`${norm(album.artistName)}|${norm(album.name)}`, album);
  const list = albumsByName.get(norm(album.name)) ?? [];
  list.push(album);
  albumsByName.set(norm(album.name), list);
}
const tracksByAlbum = new Map<string, Track[]>();
const tracksByTitle = new Map<string, Track[]>();
for (const track of tracks) {
  (tracksByAlbum.get(track.albumId) ?? tracksByAlbum.set(track.albumId, []).get(track.albumId)!).push(track);
  const key = title(track.name);
  (tracksByTitle.get(key) ?? tracksByTitle.set(key, []).get(key)!).push(track);
}
const albumById = new Map(albums.map((album) => [album.id, album]));

function findAlbum(artist: string, name: string): [Album | undefined, string] {
  const exact = albumByKey.get(`${norm(artist)}|${norm(name)}`);
  if (exact) return [exact, "exact"];
  const a = norm(artist);
  const n = norm(name);
  const artistFits = (album: Album) =>
    artist === "Various Artists" || similar(a, norm(album.artistName));
  const loose = (albumsByName.get(n) ?? []).find(artistFits);
  if (loose) return [loose, "loose"];
  const prefixed = albums.find((album) => {
    const m = norm(album.name);
    if (Math.min(m.length, n.length) < 8 || !(m.startsWith(n) || n.startsWith(m))) return false;
    const rest = m.length > n.length ? m.slice(n.length) : n.slice(m.length);
    return !/^(?:\d|pt|part|vol|live)/.test(rest) && artistFits(album);
  });
  if (prefixed) return [prefixed, "prefix"];
  const digits = (text: string) => text.replace(/\D/g, "");
  const typo = albums.find((album) => {
    const m = norm(album.name);
    return norm(album.artistName) === a && n.length >= 8 && digits(m) === digits(n) && distance(n, m) <= 2;
  });
  return typo ? [typo, "typo"] : [undefined, "missing"];
}

function findTrack(track: Apple, album: Album | undefined): [Track | undefined, string] {
  const near = (t: Track) => Math.abs(t.duration - track.duration) < 8;
  if (album) {
    const list = tracksByAlbum.get(album.id) ?? [];
    const named = list.find((t) => title(t.name) === title(track.name));
    if (named) return [named, "album+title"];
    const numbered = list.find(
      (t) => t.number === track.trackNumber && (t.disc ?? 1) === (track.discNumber || 1) && near(t),
    );
    if (numbered) return [numbered, "album+number"];
  }
  const artist = norm(track.artist);
  const candidates = (tracksByTitle.get(title(track.name)) ?? []).filter((t) => {
    const b = norm(t.artistName);
    const c = norm(albumById.get(t.albumId)?.artistName ?? "");
    return artist.includes(b) || b.includes(artist) || artist.includes(c) || c.includes(artist);
  });
  const best = candidates.find(near) ?? candidates[0];
  return best ? [best, candidates.find(near) ? "title" : "title, duration differs"] : [undefined, "missing"];
}

type Group = {
  artist: string; album: string; year: number; tracks: Apple[];
  match: string; jellyfin?: Album;
};
const groups = new Map<string, Group>();
for (const track of apple) {
  if (track.mediaKind !== "song") continue;
  const artist = track.albumArtist || (track.compilation ? "Various Artists" : track.artist);
  const key = `${norm(artist)}|${norm(track.album)}`;
  let group = groups.get(key);
  if (!group) {
    const [jellyfin, match] = track.album ? findAlbum(artist, track.album) : [undefined, "missing"];
    group = { artist, album: track.album, year: track.year, tracks: [], match, jellyfin };
    groups.set(key, group);
  }
  group.tracks.push(track);
}

const tsv = (rows: (string | number | boolean | null | undefined)[][]) =>
  rows.map((row) => row.map((v) => String(v ?? "").replace(/[\t\n]/g, " ")).join("\t")).join("\n") + "\n";
const latest = (dates: (string | null)[]) =>
  dates.filter(Boolean).sort().at(-1)?.slice(0, 10) ?? "";
const earliest = (dates: (string | null)[]) =>
  dates.filter(Boolean).sort()[0]?.slice(0, 10) ?? "";
const statuses = (list: Apple[]) =>
  [...new Set(list.map((t) => t.cloudStatus))].sort().join(",");

const trackRows: (string | number | boolean | null | undefined)[][] = [[
  "appleId", "artist", "album", "title", "disc", "number", "plays", "skips",
  "favourited", "disliked", "lastPlayed", "lastSkipped", "added", "cloudStatus",
  "match", "jellyfinTrackId", "jellyfinAlbum",
]];
const matchedTracks = new Map<string, number>();
for (const group of groups.values()) {
  for (const track of group.tracks) {
    const [jellyfin, match] = findTrack(track, group.jellyfin);
    if (jellyfin) matchedTracks.set(group.album, (matchedTracks.get(group.album) ?? 0) + 1);
    trackRows.push([
      track.persistentID, track.artist, track.album, track.name, track.discNumber,
      track.trackNumber, track.playedCount, track.skippedCount, track.favorited,
      track.disliked, track.playedDate, track.skippedDate, track.dateAdded,
      track.cloudStatus, match, jellyfin?.id,
      jellyfin ? albumById.get(jellyfin.albumId)?.name : "",
    ]);
  }
}

const sorted = [...groups.values()].sort(
  (a, b) => a.artist.localeCompare(b.artist) || a.album.localeCompare(b.album),
);
const albumRows: (string | number | boolean | null | undefined)[][] = [[
  "status", "artist", "album", "year", "tracks", "plays", "favourited",
  "lastPlayed", "added", "cloudStatus", "jellyfinAlbum", "jellyfinAlbumId",
]];
for (const group of sorted) {
  albumRows.push([
    group.match, group.artist, group.album, group.year, group.tracks.length,
    group.tracks.reduce((n, t) => n + t.playedCount, 0),
    group.tracks.filter((t) => t.favorited).length,
    latest(group.tracks.map((t) => t.playedDate)),
    earliest(group.tracks.map((t) => t.dateAdded)),
    statuses(group.tracks),
    group.jellyfin ? `${group.jellyfin.artistName} - ${group.jellyfin.name}` : "",
    group.jellyfin?.id,
  ]);
}

const seen = new Set(sorted.filter((g) => g.jellyfin).map((g) => g.jellyfin!.id));
const jellyfinOnly = [["artist", "album", "year", "jellyfinAlbumId"],
  ...albums.filter((a) => !seen.has(a.id))
    .sort((a, b) => a.artistName.localeCompare(b.artistName) || a.name.localeCompare(b.name))
    .map((a) => [a.artistName, a.name, a.year, a.id])];

const playlistRows: (string | number | boolean | null | undefined)[][] = [[
  "playlist", "position", "appleId", "artist", "album", "title", "jellyfinTrackId",
]];
const trackById = new Map(trackRows.slice(1).map((row) => [row[0] as string, row]));
for (const playlist of exported.playlists) {
  if (playlist.smart !== false) continue;
  playlist.tracks.forEach((id: string, i: number) => {
    const row = trackById.get(id);
    playlistRows.push([playlist.name, i + 1, id, row?.[1], row?.[2], row?.[3], row?.[15]]);
  });
}

await Bun.write(`${outDir}/albums.tsv`, tsv(albumRows));
await Bun.write(`${outDir}/tracks.tsv`, tsv(trackRows));
await Bun.write(`${outDir}/playlists.tsv`, tsv(playlistRows));
await Bun.write(`${outDir}/jellyfin-only.tsv`, tsv(jellyfinOnly));

const count = (status: string) => sorted.filter((g) => g.match === status).length;
const songTracks = trackRows.length - 1;
const linked = trackRows.slice(1).filter((row) => row[15]).length;
const plays = trackRows.slice(1).reduce((n, row) => n + Number(row[6]), 0);
const linkedPlays = trackRows.slice(1).filter((row) => row[15]).reduce((n, row) => n + Number(row[6]), 0);
console.log(`albums: ${sorted.length} (${count("exact")} exact, ${count("loose")} loose, ${count("missing")} missing)`);
console.log(`tracks: ${songTracks}, ${linked} linked to Jellyfin`);
console.log(`plays: ${plays}, ${linkedPlays} on linked tracks`);
console.log(`Jellyfin albums not in Apple Music: ${jellyfinOnly.length - 1}`);
