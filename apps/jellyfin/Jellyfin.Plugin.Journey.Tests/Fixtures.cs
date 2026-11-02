using System.Text.RegularExpressions;

namespace Jellyfin.Plugin.Journey.Tests;

internal static partial class Fixtures
{
    public static string Dir(string name) => Path.Combine(AppContext.BaseDirectory, "Fixtures", name);

    public static IReadOnlyList<TrackTags> Madvillainy() =>
        Directory.GetFiles(Dir("madvillainy"), "*.tags")
            .Order(StringComparer.Ordinal)
            .Select(p => new TrackTags(Path.GetFileName(p), Parse(File.ReadAllText(p))))
            .ToList();

    public static IReadOnlyList<KeyValuePair<string, string>> Parse(string text)
    {
        var fields = new List<KeyValuePair<string, string>>();
        foreach (var line in text.TrimEnd('\n').Split('\n'))
        {
            var m = Field().Match(line);
            if (m.Success)
            {
                fields.Add(new(m.Groups[1].Value, m.Groups[2].Value));
            }
            else if (fields.Count > 0)
            {
                fields[^1] = new(fields[^1].Key, fields[^1].Value + "\n" + line);
            }
        }

        return fields;
    }

    public static TrackTags Track(string path, params (string Key, string Value)[] fields) =>
        new(path, fields.Select(f => new KeyValuePair<string, string>(f.Key, f.Value)).ToList());

    [GeneratedRegex("^([A-Z][A-Z0-9_]*)=(.*)$")]
    private static partial Regex Field();
}
