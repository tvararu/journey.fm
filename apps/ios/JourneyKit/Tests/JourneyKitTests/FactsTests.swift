import Foundation
import Testing

@testable import JourneyKit

let britain = Locale(identifier: "en_GB")

func numbered(_ count: Int, discs: Int = 1) -> [Track] {
    (0..<count).map { i in
        var track = song("t\(i + 1)", "Track \(i + 1)", album: "x")
        track.disc = discs > 1 ? i * discs / count + 1 : 1
        track.number = discs > 1 ? i % (count / discs) + 1 : i + 1
        return track
    }
}

func credited(_ track: Int, _ name: String, _ kind: String, role: String = "", position: Int = 0)
    -> Credit
{
    Credit(trackId: "t\(track)", name: name, role: role, kind: kind, position: position)
}

@Test func creditsNameEachPersonOnceWithTheirRolesAndTracks() {
    let tracks = numbered(8)
    let credits =
        (1...8).flatMap {
            [credited($0, "Madlib", "Producer"), credited($0, "Madlib", "Engineer", position: 1)]
        }
        + (1...8).map { credited($0, "Daniel Dumile", "Composer", position: 2) }
        + [2, 5, 6, 7].map { credited($0, "Daniel Dumile", "Lyricist", position: 3) }
        + [credited(3, "MF DOOM", "Performer", role: "lead vocals", position: 4)]
    let summary = creditSummary(credits, tracks: tracks)
    #expect(
        summary == [
            PersonCredit(name: "Madlib", text: "Producer, engineer (all tracks)"),
            PersonCredit(name: "Daniel Dumile", text: "Composer (all tracks), lyricist (2, 5–7)"),
            PersonCredit(name: "MF DOOM", text: "Lead vocals (3)"),
        ])
}

@Test func creditsOnTwoDiscsNameTheDisc() {
    let tracks = numbered(4, discs: 2)
    let summary = creditSummary(
        [credited(2, "A", "Mixer"), credited(3, "A", "Mixer"), credited(4, "A", "Mixer")],
        tracks: tracks)
    #expect(summary.map(\.text) == ["Mixer (1.2, 2.1, 2.2)"])
}

func madvillainy(_ tags: [JourneyKit.Tag]) -> AlbumFacts {
    var album = synced("x", name: "Madvillainy", artist: idoli, year: 2004).album
    album.released = "2004-03-19"
    album.label = "Stones Throw Records"
    album.rating = 8.64
    return AlbumFacts(album: album, tags: tags, locale: britain)
}

@Test func albumFactsReadTheTags() {
    let facts = madvillainy([
        Tag("RELEASETYPE", "album"), Tag("DATE", "2004-03-23"), Tag("CATALOGNUMBER", "STH2065"),
        Tag("MEDIA", "CD"), Tag("TOTALDISCS", "2"), Tag("RELEASECOUNTRY", "XW"),
        Tag("LANGUAGE", "eng"), Tag("RYM_GENRE", "Abstract Hip Hop (108)"),
        Tag("RYM_SECONDARY_GENRE", "Jazz Rap (18)"), Tag("RYM_DESCRIPTORS", "playful"),
        Tag("RYM_DESCRIPTORS", "abstract"), Tag("RYM_RATING_VOTES", "23251"),
        Tag("RYM_RANK", "#1 for 2004"), Tag("RYM_FETCHED_AT", "2026-11-01"),
        Tag("RYM_URL", "https://rateyourmusic.com/release/album/madvillain/madvillainy/"),
    ])
    #expect(facts.releaseType == nil)
    #expect(
        facts.details == [
            Fact("Released", "19 Mar 2004"), Fact("This Edition", "23 Mar 2004"),
            Fact("Label", "Stones Throw Records"), Fact("Catalogue No.", "STH2065"),
            Fact("Format", "2 × CD"), Fact("Country", "Worldwide"), Fact("Language", "English"),
            Fact("RYM Genres", "Abstract Hip Hop, Jazz Rap"),
            Fact("Descriptors", "playful, abstract"),
        ])
    #expect(facts.rating == "8.64 · 23,251 ratings")
    #expect(facts.rank == "#1 for 2004")
    #expect(facts.fetched == "1 Nov 2026")
    #expect(facts.rymURL?.host() == "rateyourmusic.com")
}

@Test func albumFactsLeaveOutWhatIsMissing() {
    var album = synced("x", name: "Valley of Sand", artist: idoli, year: 2012).album
    album.released = "2012"
    let facts = AlbumFacts(
        album: album, tags: [Tag("RYM_TYPE", "EP"), Tag("DATE", "2012")], locale: britain)
    #expect(facts.releaseType == "EP")
    #expect(facts.details == [Fact("Released", "2012")])
    #expect(facts.rating == nil && facts.rymURL == nil)
    #expect(madvillainy([Tag("RELEASETYPE", "single")]).releaseType == "Single")
}

@Test func genresListTheirAlbums() async throws {
    var a = synced("a", name: "Madvillainy", artist: idoli, year: 2004)
    a.genres = ["Abstract Hip Hop", "Jazz Rap"]
    var b = synced("b", name: "Shades of Blue", artist: sabbath, year: 2003)
    b.genres = ["Jazz Rap"]
    let library = try await librarySynced(artists: [idoli, sabbath], albums: [a, b], tracks: [])
    var genres = library.observeGenres().makeAsyncIterator()
    #expect(
        try await genres.next()
            == [
                GenreSummary(name: "Abstract Hip Hop", albumCount: 1),
                GenreSummary(name: "Jazz Rap", albumCount: 2),
            ])
    var jazz = library.observeGenre(name: "Jazz Rap").makeAsyncIterator()
    #expect(try await jazz.next()?.map(\.id) == ["b", "a"])
}

@Test func searchFindsCreditedPeopleAndLyricLines() async throws {
    let library = try Library()
    let source = FakeSource()
    var accordion = song("t1", "Accordion", album: "a")
    accordion.hasLyrics = true
    source.state.withLock {
        $0.artists = [idoli]
        $0.albums = [synced("a", name: "Madvillainy", artist: idoli)]
        $0.synced = [
            SyncedTrack(
                track: accordion,
                credits: [
                    Credit(trackId: "t1", name: "Madlib", role: "", kind: "Producer", position: 0),
                    Credit(trackId: "t1", name: "Madlib", role: "", kind: "Engineer", position: 1),
                    Credit(trackId: "t1", name: "Madlib", role: "", kind: "Producer", position: 2),
                ])
        ]
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    try await LyricsSync(
        source: FakeLyrics([
            "t1": .success([
                LyricLine(text: "Living off borrowed time, the clock tick faster", time: 19),
                LyricLine(text: "Dick Dastardly and Muttley with sick laughter", time: 24),
            ])
        ]), library: library
    ).run()
    let credits = try await library.search("madl").credits
    #expect(
        credits.map { [$0.album.id, $0.name, $0.reads] } == [["a", "Madlib", "producer, engineer"]])
    let lyrics = try await library.search("muttley sick").lyrics
    #expect(lyrics.map(\.line) == ["Dick Dastardly and Muttley with sick laughter"])
    #expect(lyrics.first?.hit.album.id == "a")
}

@Test func trackCreditsIncludeTheISRC() async throws {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock {
        $0.albums = [synced("a", name: "A", artist: idoli)]
        $0.synced = [
            SyncedTrack(
                track: song("t1", "One", album: "a"), tags: [Tag("ISRC", "US1")],
                credits: [Credit(trackId: "t1", name: "X", role: "", kind: "Mixer", position: 0)])
        ]
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    let credits = try await library.trackCredits(trackId: "t1")
    #expect(credits.credits.map(\.name) == ["X"] && credits.isrc == ["US1"])
}
