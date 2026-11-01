import Foundation
import Testing

@testable import JourneyKit

func synced(
    _ id: String, name: String, artist: Artist, year: Int = 2000, trackCount: Int = 1
) -> SyncedAlbum {
    SyncedAlbum(
        album: Album(
            id: id, name: name, sortName: name.lowercased(), artistName: artist.name, year: year,
            genres: "", duration: 0, trackCount: trackCount, imageTag: nil,
            dateCreated: "2026-01-01T00:00:00Z"),
        artistIds: [artist.id])
}

func song(_ id: String, _ name: String, album: String, artist: String = "Artist") -> Track {
    Track(
        id: id, albumId: album, name: name, artistName: artist, disc: 1, number: 1, duration: 100,
        container: "flac")
}

func librarySynced(
    artists: [Artist], albums: [SyncedAlbum], tracks: [Track]
) async throws -> Library {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock {
        $0.artists = artists
        $0.albums = albums
        $0.tracks = tracks
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    return library
}

let idoli = Artist(id: "idoli", name: "Idoli", sortName: "idoli", imageTag: nil)
let bongRa = Artist(id: "bong", name: "Bong\u{2010}Ra", sortName: "bong\u{2010}ra", imageTag: nil)
let sabbath = Artist(id: "bs", name: "Black Sabbath", sortName: "black sabbath", imageTag: nil)

@Test func albumCountsAndLengthComeFromSyncedTracks() async throws {
    let library = try await librarySynced(
        artists: [idoli],
        albums: [synced("o", name: "Odbrana i poslednji dani", artist: idoli, trackCount: 14)],
        tracks: (1...13).map { song("t\($0)", "Track \($0)", album: "o") })
    var details = library.observeAlbum(id: "o").makeAsyncIterator()
    let album = try #require(try await details.next()??.album)
    #expect(album.trackCount == 13)
    #expect(album.duration == 1300)
}

@Test func artistsWithoutAlbumsAreHidden() async throws {
    let empty = Artist(id: "dup", name: "Idoli", sortName: "idoli", imageTag: nil)
    let library = try await librarySynced(
        artists: [idoli, empty], albums: [synced("o", name: "Odbrana", artist: idoli)], tracks: [])
    var artists = library.observeArtists().makeAsyncIterator()
    #expect(try await artists.next()?.map(\.id) == ["idoli"])
    #expect(try await library.stats().artists == 1)
}

@Test func anArtistListedTwiceOnAnAlbumCountsItOnce() async throws {
    var monolith = synced("m", name: "Monolith", artist: bongRa)
    monolith.artistIds = ["bong", "bong"]
    let library = try await librarySynced(artists: [bongRa], albums: [monolith], tracks: [])
    var artists = library.observeArtists().makeAsyncIterator()
    #expect(try await artists.next()?.first?.albumCount == 1)
}

@Test func sortingByArtistUsesTheAlbumArtistThenYear() async throws {
    let library = try await librarySynced(
        artists: [sabbath, idoli],
        albums: [
            synced("v4", name: "Vol. 4", artist: sabbath, year: 1972),
            synced("o", name: "Odbrana", artist: idoli, year: 1982),
            synced("p", name: "Paranoid", artist: sabbath, year: 1970),
        ],
        tracks: [])
    var albums = library.observeAlbums(sort: .artist).makeAsyncIterator()
    #expect(try await albums.next()?.map(\.id) == ["p", "v4", "o"])
}

@Test func searchMatchesWordPrefixesAcrossHyphensAndAccents() async throws {
    let library = try await librarySynced(
        artists: [bongRa, sabbath],
        albums: [
            synced("m", name: "Monolith", artist: bongRa),
            synced("c", name: "Café Noir", artist: sabbath),
        ],
        tracks: [song("s", "Stangblack", album: "m", artist: "Bong-Ra")])

    let hyphen = try await library.search("bong-ra")
    #expect(hyphen.artists.map(\.id) == ["bong"])
    #expect(hyphen.albums.map(\.id) == ["m"])
    #expect(hyphen.tracks.map(\.id) == ["s"])

    #expect(try await library.search("cafe").albums.map(\.id) == ["c"])
    #expect(try await library.search("black").tracks.isEmpty)
}

@Test func searchRanksTitlesThatStartWithTheQueryFirst() async throws {
    let library = try await librarySynced(
        artists: [sabbath],
        albums: [
            synced("h", name: "Heaven and Hell", artist: sabbath),
            synced("b", name: "Born Again", artist: sabbath),
        ],
        tracks: [])
    #expect(try await library.search("b").albums.map(\.id).first == "b")
}
