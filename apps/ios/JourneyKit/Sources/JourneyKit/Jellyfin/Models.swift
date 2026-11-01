import Foundation

struct ItemsPage: Decodable {
    let items: [BaseItem]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

struct NameId: Decodable {
    let name: String
    let id: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

struct BaseItem: Decodable {
    let id: String
    let name: String
    let sortName: String?
    let albumId: String?
    let albumArtist: String?
    let albumArtists: [NameId]?
    let artists: [String]?
    let productionYear: Int?
    let genres: [String]?
    let runTimeTicks: Int64?
    let childCount: Int?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let container: String?
    let imageTags: [String: String]?
    let dateCreated: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case sortName = "SortName"
        case albumId = "AlbumId"
        case albumArtist = "AlbumArtist"
        case albumArtists = "AlbumArtists"
        case artists = "Artists"
        case productionYear = "ProductionYear"
        case genres = "Genres"
        case runTimeTicks = "RunTimeTicks"
        case childCount = "ChildCount"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case container = "Container"
        case imageTags = "ImageTags"
        case dateCreated = "DateCreated"
    }

    var seconds: Double { Double(runTimeTicks ?? 0) / 10_000_000 }

    var artist: Artist {
        Artist(id: id, name: name, sortName: sortName ?? name, imageTag: imageTags?["Primary"])
    }

    var album: SyncedAlbum {
        SyncedAlbum(
            album: Album(
                id: id,
                name: name,
                sortName: sortName ?? name,
                artistName: albumArtist ?? "",
                year: productionYear,
                genres: (genres ?? []).joined(separator: ", "),
                duration: seconds,
                trackCount: childCount ?? 0,
                imageTag: imageTags?["Primary"],
                dateCreated: dateCreated ?? ""
            ),
            artistIds: (albumArtists ?? []).map(\.id)
        )
    }

    var track: Track? {
        guard let albumId else { return nil }
        return Track(
            id: id,
            albumId: albumId,
            name: name,
            artistName: (artists ?? []).joined(separator: ", "),
            disc: parentIndexNumber,
            number: indexNumber,
            duration: seconds,
            container: container
        )
    }
}

struct AuthenticationResult: Decodable {
    let accessToken: String
    let user: User

    struct User: Decodable {
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "Id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}
