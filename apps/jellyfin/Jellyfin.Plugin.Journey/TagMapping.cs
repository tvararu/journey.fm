using System.Globalization;
using System.Text.RegularExpressions;

namespace Jellyfin.Plugin.Journey;

public sealed record TrackTags(string Path, IReadOnlyList<KeyValuePair<string, string>> Fields);

public sealed record Credit(string Name, string Kind);

public sealed class ItemFields
{
    public List<string> Tags { get; } = [];

    public Dictionary<string, string> ProviderIds { get; } = [];

    public List<Credit> People { get; } = [];

    public DateTime? PremiereDate { get; set; }

    public float? CommunityRating { get; set; }
}

public sealed record AlbumMapping(ItemFields Album, IReadOnlyDictionary<string, ItemFields> Tracks);

public static partial class TagMapping
{
    public const string RateYourMusic = "RateYourMusic";
    public const string AcoustId = "AcoustId";
    public const string LrcLib = "LrcLib";

    public static readonly IReadOnlySet<string> LeftToJellyfin = new HashSet<string>
    {
        "TITLE", "ALBUM", "ARTIST", "ARTISTS", "ALBUMARTIST", "GENRE", "LABEL", "COMPOSER", "TRACKNUMBER",
        "DISCNUMBER", "MUSICBRAINZ_ALBUMID", "MUSICBRAINZ_RELEASEGROUPID", "MUSICBRAINZ_ALBUMARTISTID",
        "MUSICBRAINZ_TRACKID", "MUSICBRAINZ_RELEASETRACKID", "MUSICBRAINZ_ARTISTID", "LYRICS",
    };

    public static readonly IReadOnlyDictionary<string, string> Credits = new Dictionary<string, string>
    {
        ["LYRICIST"] = "Lyricist",
        ["WRITER"] = "Writer",
        ["ARRANGER"] = "Arranger",
        ["CONDUCTOR"] = "Conductor",
        ["PRODUCER"] = "Producer",
        ["ENGINEER"] = "Engineer",
        ["MIXER"] = "Mixer",
        ["REMIXER"] = "Remixer",
    };

    public static readonly IReadOnlySet<string> Native = new HashSet<string>
    {
        "RYM_RATING_SCORE", "RYM_ID", "ACOUSTID_ID", "LRCLIB_ID",
    };

    public static readonly IReadOnlyList<string> TrackProviderIds = [AcoustId, LrcLib];

    public static readonly IReadOnlyList<string> AlbumProviderIds = [RateYourMusic];

    private static readonly IReadOnlyDictionary<string, string> TrackIdKeys = new Dictionary<string, string>
    {
        ["ACOUSTID_ID"] = AcoustId,
        ["LRCLIB_ID"] = LrcLib,
    };

    public static AlbumMapping Map(IReadOnlyList<TrackTags> tracks)
    {
        var album = new ItemFields();
        var byTrack = new Dictionary<string, ItemFields>();
        var tagValues = new List<Dictionary<string, List<string>>>();
        foreach (var track in tracks)
        {
            var fields = new ItemFields();
            var tags = new Dictionary<string, List<string>>();
            foreach (var (rawKey, value) in track.Fields)
            {
                var key = rawKey.ToUpperInvariant();
                if (LeftToJellyfin.Contains(key))
                {
                    continue;
                }

                if (key == "ORIGINALDATE")
                {
                    fields.PremiereDate = ParseDate(value);
                }

                if (Credits.TryGetValue(key, out var kind))
                {
                    fields.People.Add(new Credit(value, kind));
                }
                else if (TrackIdKeys.TryGetValue(key, out var id))
                {
                    fields.ProviderIds[id] = value;
                }
                else if (key == "RYM_ID")
                {
                    album.ProviderIds.TryAdd(RateYourMusic, value);
                }
                else if (key == "RYM_RATING_SCORE")
                {
                    album.CommunityRating ??= ParseRating(value);
                }
                else
                {
                    if (!tags.TryGetValue(key, out var values))
                    {
                        tags[key] = values = [];
                    }

                    values.AddRange(key == "RYM_DESCRIPTORS"
                        ? value.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                        : [value]);
                }
            }

            byTrack[track.Path] = fields;
            tagValues.Add(tags);
        }

        album.PremiereDate = byTrack.Values.Select(f => f.PremiereDate).Where(d => d.HasValue).Min();

        foreach (var key in tagValues.SelectMany(t => t.Keys).Distinct().ToList())
        {
            var first = tagValues[0].GetValueOrDefault(key);
            if (first is not null && tagValues.All(t => t.TryGetValue(key, out var v) && v.SequenceEqual(first)))
            {
                album.Tags.AddRange(first.Select(v => $"{key}:{v}"));
                continue;
            }

            for (var i = 0; i < tracks.Count; i++)
            {
                if (tagValues[i].TryGetValue(key, out var values))
                {
                    byTrack[tracks[i].Path].Tags.AddRange(values.Select(v => $"{key}:{v}"));
                }
            }
        }

        return new AlbumMapping(album, byTrack);
    }

    public static ItemFields MapAlone(TrackTags track)
    {
        var mapping = Map([track]);
        var fields = mapping.Tracks[track.Path];
        fields.Tags.InsertRange(0, mapping.Album.Tags);
        return fields;
    }

    public static string[] MergeTags(IEnumerable<string> existing, IEnumerable<string> mapped) =>
        existing.Where(t => !OwnedTag().IsMatch(t)).Concat(mapped).Distinct(StringComparer.Ordinal).ToArray();

    public static string? AlbumArtistSort(IEnumerable<IReadOnlyList<TrackTags>> albums)
    {
        var values = albums
            .Select(tracks => tracks.SelectMany(t => t.Fields)
                .Where(f => f.Key.Equals("ALBUMARTISTSORT", StringComparison.OrdinalIgnoreCase))
                .Select(f => f.Value)
                .FirstOrDefault())
            .OfType<string>()
            .Where(v => v.Length > 0)
            .ToList();
        return values.GroupBy(v => v, StringComparer.Ordinal)
            .OrderByDescending(g => g.Count())
            .ThenBy(g => values.IndexOf(g.Key))
            .Select(g => g.Key)
            .FirstOrDefault();
    }

    public static DateTime? ParseDate(string value) =>
        DateTime.TryParseExact(
            value.Trim(),
            ["yyyy-MM-dd", "yyyy-MM", "yyyy"],
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var date)
            ? date
            : null;

    private static float? ParseRating(string value) =>
        float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var score)
            ? MathF.Round(score * 2, 2)
            : null;

    [GeneratedRegex("^[A-Z0-9_]+:")]
    private static partial Regex OwnedTag();
}
