namespace Jellyfin.Plugin.Journey;

public static class TagReader
{
    public static IReadOnlyList<KeyValuePair<string, string>> Read(string path)
    {
        using var file = TagLib.File.Create(path);
        if (file.GetTag(TagLib.TagTypes.Xiph) is not TagLib.Ogg.XiphComment xiph)
        {
            return [];
        }

        var fields = new List<KeyValuePair<string, string>>();
        foreach (var name in xiph)
        {
            var key = name.ToUpperInvariant();
            fields.AddRange(xiph.GetField(name).Select(value => new KeyValuePair<string, string>(key, value)));
        }

        return fields;
    }
}
