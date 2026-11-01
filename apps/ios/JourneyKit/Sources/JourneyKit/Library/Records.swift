import Foundation
import GRDB

public struct Artist: Codable, Sendable, Equatable, Identifiable, FetchableRecord,
    PersistableRecord
{
    public var id: String
    public var name: String
    public var sortName: String
    public var imageTag: String?
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
}

public struct SyncedAlbum: Sendable, Equatable {
    public var album: Album
    public var artistIds: [String]

    public init(album: Album, artistIds: [String]) {
        self.album = album
        self.artistIds = artistIds
    }
}

struct SyncState: Codable, FetchableRecord, PersistableRecord {
    var id = 1
    var lastSync: Date?
    var lastFullSync: Date?
}
