import Foundation
import GRDB

public struct Artist: Codable, Sendable, Equatable, Identifiable, FetchableRecord,
    PersistableRecord
{
    public var id: String
    public var name: String
    public var sortName: String
    public var imageTag: String?
    public var overview: String?
}

public struct Album: Codable, Sendable, Equatable, Identifiable, FetchableRecord,
    PersistableRecord
{
    public var id: String
    public var name: String
    public var sortName: String
    public var artistName: String
    public var year: Int?
    public var genres: String
    public var duration: Double
    public var trackCount: Int
    public var imageTag: String?
    public var dateCreated: String
    public var artistSortName = ""
    public var artistId: String?
    public var released: String?
    public var rating: Double?
    public var label: String?
    public var gain: Double?
    public var peak: Double?
}

public struct AlbumArtist: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public var albumId: String
    public var artistId: String
    public var position: Int
}

public struct Track: Codable, Sendable, Equatable, Identifiable, FetchableRecord,
    PersistableRecord
{
    public var id: String
    public var albumId: String
    public var name: String
    public var artistName: String
    public var disc: Int?
    public var number: Int?
    public var duration: Double
    public var container: String?
    public var gain: Double?
    public var peak: Double?
    public var hasLyrics: Bool?
    public var etag: String?
}

public struct Tag: Codable, Sendable, Equatable, Hashable {
    public var key: String
    public var value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

extension [Tag] {
    public func values(_ key: String) -> [String] { filter { $0.key == key }.map(\.value) }

    public func first(_ key: String) -> String? { first { $0.key == key }?.value }
}

public struct Credit: Codable, Sendable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    public var trackId: String
    public var name: String
    public var role: String
    public var kind: String
    public var position: Int

    public init(trackId: String, name: String, role: String, kind: String, position: Int) {
        self.trackId = trackId
        self.name = name
        self.role = role
        self.kind = kind
        self.position = position
    }

    public var reads: String { role.isEmpty ? kind.lowercased() : role }
}

struct AlbumTag: Codable, FetchableRecord, PersistableRecord {
    var albumId: String
    var key: String
    var value: String
    var position: Int
}

struct TrackTag: Codable, FetchableRecord, PersistableRecord {
    var trackId: String
    var key: String
    var value: String
    var position: Int
}

struct AlbumGenre: Codable, FetchableRecord, PersistableRecord {
    var albumId: String
    var name: String
    var position: Int
}

public struct SyncedAlbum: Sendable, Equatable {
    public var album: Album
    public var artistIds: [String]
    public var tags: [Tag]
    public var genres: [String]

    public init(album: Album, artistIds: [String], tags: [Tag] = [], genres: [String] = []) {
        self.album = album
        self.artistIds = artistIds
        self.tags = tags
        self.genres = genres
    }
}

public struct SyncedTrack: Sendable, Equatable {
    public var track: Track
    public var tags: [Tag]
    public var credits: [Credit]

    public init(track: Track, tags: [Tag] = [], credits: [Credit] = []) {
        self.track = track
        self.tags = tags
        self.credits = credits
    }
}

struct SyncState: Codable, FetchableRecord, PersistableRecord {
    var id = 1
    var lastSync: Date?
    var lastFullSync: Date?
}
