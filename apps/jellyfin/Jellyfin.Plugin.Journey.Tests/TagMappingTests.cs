using Xunit;

namespace Jellyfin.Plugin.Journey.Tests;

public class TagMappingTests
{
    private static readonly AlbumMapping Madvillainy = TagMapping.Map(Fixtures.Madvillainy());

    [Fact]
    public void ReleaseDataGoesOnTheAlbum()
    {
        var album = Madvillainy.Album;
        Assert.Equal(new DateTime(2004, 3, 19), album.PremiereDate);
        Assert.Equal(8.64f, album.CommunityRating);
        Assert.Equal("142671", album.ProviderIds[TagMapping.RateYourMusic]);
        string[] expected =
        [
            "DATE:2004-03-23", "RELEASETYPE:album", "CATALOGNUMBER:STH2065", "ALBUMARTISTSORT:Madvillain",
            "RYM_SECONDARY_GENRE:Jazz Rap (18)", "RYM_DESCRIPTORS:playful", "RYM_RANK:#1 for 2004, #9 overall",
            "TOTALTRACKS:22", "REPLAYGAIN_ALBUM_PEAK:1.00000000", "CATALOGUED_AT:2026-11-02",
        ];
        foreach (var tag in expected)
        {
            Assert.Contains(tag, album.Tags);
        }
    }

    [Fact]
    public void TrackDataGoesOnTheTrack()
    {
        var track = Madvillainy.Tracks["01.tags"];
        Assert.Equal(new DateTime(2004, 3, 19), track.PremiereDate);
        Assert.Contains(new Credit("Daniel Dumile", "Lyricist"), track.People);
        Assert.Contains(new Credit("Peanut Butter Wolf", "Producer"), track.People);
        Assert.Contains(new Credit("Dave Cooley", "Mixer"), track.People);
        Assert.DoesNotContain(track.People, p => p.Name == "Otis Jackson Jr.");
        Assert.Contains("PERFORMER:MF DOOM (lead vocals)", track.Tags);
        Assert.Contains("ISRC:US2S70465001", track.Tags);
        Assert.Contains("REPLAYGAIN_TRACK_PEAK:0.95852661", track.Tags);
        Assert.DoesNotContain("DATE:2004-03-23", track.Tags);
        Assert.Equal("1bd79e69-4915-46bb-933b-0787df19752c", track.ProviderIds[TagMapping.AcoustId]);
        Assert.Equal("27139463", track.ProviderIds[TagMapping.LrcLib]);
    }

    [Fact]
    public void EveryKeyInTheFilesIsAccountedFor()
    {
        var tagged = Madvillainy.Tracks.Values.Append(Madvillainy.Album)
            .SelectMany(f => f.Tags)
            .Select(t => t[..t.IndexOf(':')])
            .ToHashSet();
        var keys = Fixtures.Madvillainy().SelectMany(t => t.Fields).Select(f => f.Key).Distinct();
        foreach (var key in keys)
        {
            Assert.True(
                TagMapping.LeftToJellyfin.Contains(key) || TagMapping.Credits.ContainsKey(key)
                    || TagMapping.Native.Contains(key) || tagged.Contains(key),
                $"{key} is dropped");
        }
    }

    [Fact]
    public void TagsLeftToJellyfinAndNativeOnesNeverBecomeTags()
    {
        var keys = Madvillainy.Tracks.Values.Append(Madvillainy.Album)
            .SelectMany(f => f.Tags)
            .Select(t => t[..t.IndexOf(':')]);
        Assert.DoesNotContain(keys, k =>
            TagMapping.LeftToJellyfin.Contains(k) || TagMapping.Credits.ContainsKey(k) || TagMapping.Native.Contains(k));
    }

    [Fact]
    public void AOneTrackAlbumPutsItsTagsOnTheAlbum()
    {
        var mapping = TagMapping.Map([Fixtures.Track("a", ("RELEASETYPE", "single"), ("ISRC", "X1"))]);
        Assert.Equal(new[] { "RELEASETYPE:single", "ISRC:X1" }, mapping.Album.Tags);
        Assert.Empty(mapping.Tracks["a"].Tags);
    }

    [Fact]
    public void ATagThatDiffersOrIsMissingStaysOnTheTracks()
    {
        var mapping = TagMapping.Map(
        [
            Fixtures.Track("a", ("MEDIA", "CD"), ("BARCODE", "1")),
            Fixtures.Track("b", ("MEDIA", "Vinyl")),
        ]);
        Assert.Empty(mapping.Album.Tags);
        Assert.Equal(new[] { "MEDIA:CD", "BARCODE:1" }, mapping.Tracks["a"].Tags);
        Assert.Equal(new[] { "MEDIA:Vinyl" }, mapping.Tracks["b"].Tags);
    }

    [Fact]
    public void RepeatedTagsAndDescriptorsGiveOneEntryEach()
    {
        var mapping = TagMapping.Map(
        [
            Fixtures.Track("a", ("RYM_GENRE", "Drone (1)"), ("RYM_GENRE", "Ambient (2)"), ("RYM_DESCRIPTORS", "dark, slow,  heavy")),
        ]);
        Assert.Equal(
            new[] { "RYM_GENRE:Drone (1)", "RYM_GENRE:Ambient (2)", "RYM_DESCRIPTORS:dark", "RYM_DESCRIPTORS:slow", "RYM_DESCRIPTORS:heavy" },
            mapping.Album.Tags);
    }

    [Fact]
    public void OriginalDateDatesTheItemsAndDateBecomesATag()
    {
        var mapping = TagMapping.Map(
        [
            Fixtures.Track("a", ("ORIGINALDATE", "1984"), ("DATE", "2005-03-21")),
            Fixtures.Track("b", ("ORIGINALDATE", "1959-09"), ("DATE", "2005-03-21")),
        ]);
        Assert.Equal(new DateTime(1984, 1, 1), mapping.Tracks["a"].PremiereDate);
        Assert.Equal(new DateTime(1959, 9, 1), mapping.Tracks["b"].PremiereDate);
        Assert.Equal(new DateTime(1959, 9, 1), mapping.Album.PremiereDate);
        Assert.Equal(new[] { "DATE:2005-03-21" }, mapping.Album.Tags);
        Assert.Null(TagMapping.ParseDate("someday"));
    }

    [Fact]
    public void UnknownAndLowerCaseKeysBecomeUpperCaseTags()
    {
        var mapping = TagMapping.Map([Fixtures.Track("a", ("MOOD", "calm"), ("isrc", "X1"))]);
        Assert.Equal(new[] { "MOOD:calm", "ISRC:X1" }, mapping.Album.Tags);
    }

    [Fact]
    public void ATrackOnItsOwnKeepsEveryTag()
    {
        var fields = TagMapping.MapAlone(Fixtures.Track("a", ("RELEASETYPE", "album"), ("ISRC", "X1"), ("ORIGINALDATE", "2001")));
        Assert.Equal(new[] { "RELEASETYPE:album", "ISRC:X1" }, fields.Tags);
        Assert.Equal(new DateTime(2001, 1, 1), fields.PremiereDate);
    }

    [Fact]
    public void MergingReplacesOwnedTagsAndKeepsOthers()
    {
        var merged = TagMapping.MergeTags(["favourite", "DATE:1999", "Mood:x"], ["DATE:2004-03-23", "ISRC:X1"]);
        Assert.Equal(new[] { "favourite", "Mood:x", "DATE:2004-03-23", "ISRC:X1" }, merged);
    }

    [Fact]
    public void TheAlbumArtistSortFollowsMostAlbumsThenTheFirst()
    {
        static IReadOnlyList<TrackTags> Album(string? sort) =>
            [sort is null ? Fixtures.Track("t") : Fixtures.Track("t", ("ALBUMARTISTSORT", sort))];

        Assert.Equal("Robbins, Marty", TagMapping.AlbumArtistSort([Album("Marty Robbins"), Album("Robbins, Marty"), Album("Robbins, Marty")]));
        Assert.Equal("A", TagMapping.AlbumArtistSort([Album("A"), Album("B")]));
        Assert.Null(TagMapping.AlbumArtistSort([Album(null)]));
    }
}
