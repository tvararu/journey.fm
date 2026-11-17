import Foundation
import Testing

@testable import JourneyKit

@Test func slugsFollowRateYourMusic() {
    #expect(Slug.make("Far Beyond Driven") == "far-beyond-driven")
    #expect(Slug.make("I'm Broken") == "im-broken")
    #expect(Slug.make("Mötley Crüe") == "motley-crue")
    #expect(Slug.make("Drum & Bass") == "drum-and-bass")
}

@Test func linksPreferTheStoredRateYourMusicPath() async throws {
    var tagged = synced("p", name: "Paranoid", artist: sabbath)
    tagged.tags = [
        Tag("RYM_URL", "https://rateyourmusic.com/release/album/black-sabbath/paranoid/")
    ]
    var genred = synced("o", name: "Odbrana i poslednji dani", artist: idoli)
    genred.genres = ["Post-Punk"]
    let library = try await librarySynced(
        artists: [sabbath, idoli], albums: [tagged, genred], tracks: [])

    #expect(
        try await library.albumId(release: ["release", "album", "black-sabbath", "paranoid"]) == "p"
    )
    #expect(
        try await library.albumId(release: ["release", "ep", "idoli", "odbrana-i-poslednji-dani"])
            == "o")
    #expect(try await library.albumId(release: ["release", "album", "idoli", "paranoid"]) == nil)
    #expect(try await library.artistId(slug: "black-sabbath") == "bs")
    #expect(try await library.artistId(slug: "idoli") == "idoli")
    #expect(try await library.genre(slug: "post-punk") == "Post-Punk")
}
