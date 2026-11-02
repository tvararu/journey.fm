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

struct Person: Decodable {
    let name: String
    let type: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case type = "Type"
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
    var tags: [String]?
    var people: [Person]?
    var studios: [NameId]?
    var communityRating: Double?
    var hasLyrics: Bool?
    var etag: String?
    var overview: String?

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
        case tags = "Tags"
        case people = "People"
        case studios = "Studios"
        case communityRating = "CommunityRating"
        case hasLyrics = "HasLyrics"
        case etag = "Etag"
        case overview = "Overview"
    }

    var seconds: Double { Double(runTimeTicks ?? 0) / 10_000_000 }

    var catalogueTags: [Tag] {
        (tags ?? []).compactMap { tag in
            guard let colon = tag.firstIndex(of: ":") else { return nil }
            let key = tag[..<colon]
            guard !key.isEmpty, key.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" })
            else { return nil }
            return Tag(String(key), String(tag[tag.index(after: colon)...]))
        }
    }

    var artist: Artist {
        Artist(
            id: id, name: name, sortName: sortName ?? name, imageTag: imageTags?["Primary"],
            overview: overview.flatMap { $0.isEmpty ? nil : $0 })
    }

    var album: SyncedAlbum {
        let tags = catalogueTags
        return SyncedAlbum(
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
                dateCreated: dateCreated ?? "",
                released: tags.first("ORIGINALDATE"),
                rating: communityRating,
                label: studios?.first?.name,
                gain: tags.first("REPLAYGAIN_ALBUM_GAIN").flatMap(decibels),
                peak: tags.first("REPLAYGAIN_ALBUM_PEAK").flatMap { Double($0) }
            ),
            artistIds: (albumArtists ?? []).map(\.id),
            tags: tags,
            genres: genres ?? []
        )
    }

    var track: SyncedTrack? {
        guard let albumId else { return nil }
        let tags = catalogueTags
        let people = (people ?? []).filter { $0.type != "Artist" && $0.type != "AlbumArtist" }
            .map { (name: $0.name, role: "", kind: $0.type ?? "") }
        let performers = tags.values("PERFORMER").map(performer)
        let credits = (people + performers).enumerated().map { position, credit in
            Credit(
                trackId: id, name: credit.name, role: credit.role, kind: credit.kind,
                position: position)
        }
        return SyncedTrack(
            track: Track(
                id: id,
                albumId: albumId,
                name: name,
                artistName: (artists ?? []).joined(separator: ", "),
                disc: parentIndexNumber,
                number: indexNumber,
                duration: seconds,
                container: container,
                gain: tags.first("REPLAYGAIN_TRACK_GAIN").flatMap(decibels),
                peak: tags.first("REPLAYGAIN_TRACK_PEAK").flatMap { Double($0) },
                hasLyrics: hasLyrics ?? false,
                etag: etag
            ),
            tags: tags,
            credits: credits
        )
    }
}

func decibels(_ value: String) -> Double? {
    Double(value.replacingOccurrences(of: "dB", with: "").trimmingCharacters(in: .whitespaces))
}

func performer(_ value: String) -> (name: String, role: String, kind: String) {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "("), open > trimmed.startIndex
    else { return (trimmed, "", "Performer") }
    let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
    let role = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
    return (name, String(role).trimmingCharacters(in: .whitespaces), "Performer")
}

struct LyricsResponse: Decodable {
    struct Line: Decodable {
        let text: String?
        let start: Int64?

        enum CodingKeys: String, CodingKey {
            case text = "Text"
            case start = "Start"
        }
    }

    let lyrics: [Line]?

    enum CodingKeys: String, CodingKey {
        case lyrics = "Lyrics"
    }

    var lines: [LyricLine] {
        (lyrics ?? []).map { line in
            LyricLine(text: line.text ?? "", time: line.start.map { Double($0) / 10_000_000 })
        }
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
