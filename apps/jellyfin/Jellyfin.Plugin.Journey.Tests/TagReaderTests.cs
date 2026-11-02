using Xunit;

namespace Jellyfin.Plugin.Journey.Tests;

public class TagReaderTests
{
    private static readonly IReadOnlyList<KeyValuePair<string, string>> Fields =
        TagReader.Read(Path.Combine(AppContext.BaseDirectory, "Fixtures", "tagged.flac"));

    [Fact]
    public void RepeatedTagsKeepEveryValueInOrder()
    {
        Assert.Equal(new[] { "Ambient (1)", "Drone (2)" }, Fields.Where(f => f.Key == "RYM_GENRE").Select(f => f.Value));
    }

    [Fact]
    public void KeysAreUpperCased()
    {
        Assert.Contains(new KeyValuePair<string, string>("ISRC", "XX0000000001"), Fields);
    }

    [Fact]
    public void MultiLineValuesSurvive()
    {
        Assert.Equal("[00:01.00]one\n[00:02.00]two", Fields.Single(f => f.Key == "LYRICS").Value);
    }
}
