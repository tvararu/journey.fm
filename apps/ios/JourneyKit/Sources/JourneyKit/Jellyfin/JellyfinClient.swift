import Foundation

public struct Session: Codable, Sendable, Equatable {
    public var server: URL
    public var userId: String
    public var token: String
    public var deviceId: String
    public var deviceName: String
    public var username: String?
}

public enum JellyfinError: LocalizedError, Equatable {
    case unauthorized
    case status(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "The server rejected the sign-in."
        case .status(let code): "The server answered with HTTP \(code)."
        }
    }
}

public struct JellyfinClient: LibrarySource {
    public static let version = "0.1.0"
    static let pageSize = 1000

    public let session: Session
    let urlSession: URLSession

    public init(session: Session, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    public static func signIn(
        server: URL, username: String, password: String, deviceName: String,
        deviceId: String = UUID().uuidString, urlSession: URLSession = .shared
    ) async throws -> Session {
        var request = URLRequest(url: server.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            authorization(deviceId: deviceId, deviceName: deviceName, token: nil),
            forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])
        let (data, response) = try await urlSession.data(for: request)
        try check(response)
        let result = try JSONDecoder().decode(AuthenticationResult.self, from: data)
        return Session(
            server: server, userId: result.user.id, token: result.accessToken,
            deviceId: deviceId, deviceName: deviceName, username: username)
    }

    public func artists() async throws -> [Artist] {
        let page: ItemsPage = try await get(
            "Artists/AlbumArtists",
            [
                .init(name: "userId", value: session.userId),
                .init(name: "Fields", value: "SortName"),
                .init(name: "EnableUserData", value: "false"),
                .init(name: "EnableTotalRecordCount", value: "false"),
                .init(name: "EnableImageTypes", value: "Primary"),
                .init(name: "ImageTypeLimit", value: "1"),
            ])
        return page.items.map(\.artist)
    }

    public func albums(since: Date?) async throws -> [SyncedAlbum] {
        try await items(
            type: "MusicAlbum", fields: "SortName,Genres,ChildCount,DateCreated", images: true,
            since: since
        ).map(\.album)
    }

    public func tracks(since: Date?) async throws -> [Track] {
        try await items(type: "Audio", fields: "", images: false, since: since).compactMap(\.track)
    }

    public func imageURL(itemId: String, tag: String, maxWidth: Int) -> URL {
        session.server.appending(path: "Items/\(itemId)/Images/Primary").appending(queryItems: [
            .init(name: "tag", value: tag),
            .init(name: "maxWidth", value: String(maxWidth)),
            .init(name: "quality", value: "90"),
        ])
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request(url))
        try Self.check(response)
        return data
    }

    func items(type: String, fields: String, images: Bool, since: Date?) async throws -> [BaseItem]
    {
        var all: [BaseItem] = []
        var seen = Set<String>()
        while true {
            var query: [URLQueryItem] = [
                .init(name: "userId", value: session.userId),
                .init(name: "IncludeItemTypes", value: type),
                .init(name: "Recursive", value: "true"),
                .init(name: "Fields", value: fields),
                .init(name: "SortBy", value: "SortName"),
                .init(name: "StartIndex", value: String(all.count)),
                .init(name: "Limit", value: String(Self.pageSize)),
                .init(name: "EnableUserData", value: "false"),
                .init(name: "EnableTotalRecordCount", value: "false"),
            ]
            query +=
                images
                ? [
                    .init(name: "EnableImageTypes", value: "Primary"),
                    .init(name: "ImageTypeLimit", value: "1"),
                ]
                : [.init(name: "EnableImages", value: "false")]
            if let since {
                query.append(.init(name: "MinDateLastSaved", value: since.ISO8601Format()))
            }
            let page: ItemsPage = try await get("Items", query)
            for item in page.items where seen.insert(item.id).inserted {
                all.append(item)
            }
            if page.items.count < Self.pageSize { return all }
        }
    }

    func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        let url = session.server.appending(path: path).appending(queryItems: query)
        let (data, response) = try await urlSession.data(for: request(url))
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            Self.authorization(
                deviceId: session.deviceId, deviceName: session.deviceName, token: session.token),
            forHTTPHeaderField: "Authorization")
        return request
    }

    static func authorization(deviceId: String, deviceName: String, token: String?) -> String {
        var value =
            #"MediaBrowser Client="journey.fm", Device="\#(deviceName)", DeviceId="\#(deviceId)", Version="\#(version)""#
        if let token { value += #", Token="\#(token)""# }
        return value
    }

    static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return }
        if status == 401 { throw JellyfinError.unauthorized }
        if !(200..<300).contains(status) { throw JellyfinError.status(status) }
    }
}
