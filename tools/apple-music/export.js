function run(argv) {
  const music = Application("Music");
  const tracks = music.libraryPlaylists[0].tracks;
  const fields = [
    "persistentID", "databaseID", "name", "artist", "albumArtist", "album",
    "composer", "genre", "grouping", "work", "movement", "movementNumber",
    "movementCount", "year", "releaseDate", "trackNumber", "trackCount",
    "discNumber", "discCount", "compilation", "duration", "start", "finish",
    "bpm", "comment", "playedCount", "playedDate", "skippedCount",
    "skippedDate", "rating", "ratingKind", "albumRating", "albumRatingKind",
    "favorited", "disliked", "albumFavorited", "albumDisliked", "dateAdded",
    "modificationDate", "cloudStatus", "kind", "mediaKind", "bitRate",
    "sampleRate", "size", "enabled", "sortName", "sortArtist",
    "sortAlbumArtist", "sortAlbum", "sortComposer", "show", "episodeNumber",
    "seasonNumber", "category", "description", "lyrics",
  ];
  const columns = {};
  for (const field of fields) {
    try {
      columns[field] = tracks[field]();
    } catch (error) {
      console.log(`skipped ${field}: ${error}`);
    }
  }
  const ids = columns.persistentID;
  const rows = ids.map((_, i) => {
    const row = {};
    for (const field in columns) {
      const value = columns[field][i];
      row[field] = value instanceof Date ? value.toISOString() : value;
    }
    return row;
  });
  const fileTracks = music.libraryPlaylists[0].fileTracks;
  try {
    const paths = fileTracks.persistentID();
    const locations = fileTracks.location();
    const byId = {};
    paths.forEach((id, i) => (byId[id] = locations[i] ? locations[i].toString() : null));
    for (const row of rows) if (row.persistentID in byId) row.location = byId[row.persistentID];
  } catch (error) {
    console.log(`skipped locations: ${error}`);
  }

  const playlists = music.playlists().map((playlist) => {
    const entry = {
      name: playlist.name(),
      persistentID: playlist.persistentID(),
      specialKind: playlist.specialKind(),
      smart: (() => { try { return playlist.smart(); } catch (_) { return null; } })(),
      parent: (() => { try { return playlist.parent.persistentID(); } catch (_) { return null; } })(),
      description: (() => { try { return playlist.description(); } catch (_) { return null; } })(),
      tracks: (() => { try { return playlist.tracks.persistentID(); } catch (_) { return []; } })(),
    };
    return entry;
  });

  return JSON.stringify({
    snapshot: new Date().toISOString(),
    trackCount: rows.length,
    fields: Object.keys(columns),
    tracks: rows,
    playlists,
  });
}
