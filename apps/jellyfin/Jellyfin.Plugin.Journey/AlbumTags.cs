using System.Collections.Concurrent;
using MediaBrowser.Controller.Entities.Audio;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.Journey;

public class AlbumTags(ILogger<AlbumTags> logger)
{
    private readonly ConcurrentDictionary<string, (DateTime Modified, IReadOnlyList<KeyValuePair<string, string>> Fields)> _cache =
        new(StringComparer.Ordinal);

    public IReadOnlyList<KeyValuePair<string, string>>? Read(string path)
    {
        try
        {
            var modified = File.GetLastWriteTimeUtc(path);
            if (_cache.TryGetValue(path, out var hit) && hit.Modified == modified)
            {
                return hit.Fields;
            }

            var fields = TagReader.Read(path).Where(f => f.Key != "LYRICS").ToList();
            _cache[path] = (modified, fields);
            return fields;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
            or TagLib.CorruptFileException or TagLib.UnsupportedFormatException)
        {
            logger.LogWarning(ex, "Can't read the tags of {Path}", path);
            return null;
        }
    }

    public IReadOnlyList<TrackTags> ForAlbum(MusicAlbum album)
    {
        var tracks = new List<TrackTags>();
        foreach (var item in album.GetRecursiveChildren(i => i is Audio))
        {
            if (string.IsNullOrEmpty(item.Path))
            {
                continue;
            }

            var fields = Read(item.Path);
            if (fields is not null)
            {
                tracks.Add(new TrackTags(item.Path, fields));
            }
        }

        return tracks;
    }
}
