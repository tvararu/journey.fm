import Foundation
import GRDB

public enum Slug {
    public static func make(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
    }
}

extension Library {
    static let rym = "https://rateyourmusic.com/"

    public func albumId(release path: [String]) async throws -> String? {
        guard path.count == 4, path[0] == "release" else { return nil }
        let url = Self.rym + path.joined(separator: "/")
        return try await db.read { db in
            if let id = try String.fetchOne(
                db,
                sql: "SELECT albumId FROM albumTag WHERE key = 'RYM_URL' AND value IN (?, ?)",
                arguments: [url, url + "/"])
            {
                return id
            }
            return try Album.fetchAll(db).first {
                Slug.make($0.artistName) == path[2] && Slug.make($0.name) == path[3]
            }?.id
        }
    }

    public func artistId(slug: String) async throws -> String? {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT album.artistId, albumTag.value FROM albumTag
                    JOIN album ON album.id = albumTag.albumId
                    WHERE albumTag.key = 'RYM_URL' AND albumTag.value LIKE ?
                    """, arguments: ["%/\(slug)/%"])
            for row in rows {
                let parts = (row["value"] as String).split(separator: "/")
                if parts.count > 4, parts[4] == slug, let id = row["artistId"] as String? {
                    return id
                }
            }
            return try Artist.fetchAll(db).first { Slug.make($0.name) == slug }?.id
        }
    }

    public func genre(slug: String) async throws -> String? {
        try await db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT name FROM albumGenre")
                .first { Slug.make($0) == slug }
        }
    }
}
