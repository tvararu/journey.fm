import Foundation

public struct Fact: Sendable, Equatable, Identifiable {
    public var label: String
    public var value: String
    public var id: String { label }

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

public struct AlbumFacts: Sendable, Equatable {
    public var releaseType: String?
    public var details: [Fact] = []
    public var rating: String?
    public var rank: String?
    public var fetched: String?
    public var rymURL: URL?

    public init(album: Album, tags: [Tag], locale: Locale = .current) {
        if let type = tags.first("RYM_TYPE") ?? tags.first("RELEASETYPE").map(capitalised),
            type.lowercased() != "album"
        {
            releaseType = type
        }
        let date = { (value: String) in Self.date(value, locale: locale) }
        let released = album.released
        var details: [Fact?] = [
            Fact("Released", released.map(date) ?? album.year.map(String.init) ?? "")
        ]
        if let edition = tags.first("DATE"), edition != released {
            details.append(Fact("This Edition", date(edition)))
        }
        let format = tags.first("MEDIA").map { media in
            let discs = tags.first("TOTALDISCS").flatMap { Int($0) } ?? 1
            return discs > 1 && media.first?.isNumber != true ? "\(discs) × \(media)" : media
        }
        let languages = tags.values("LANGUAGE").map {
            locale.localizedString(forLanguageCode: $0) ?? $0
        }
        let genres = (tags.values("RYM_GENRE") + tags.values("RYM_SECONDARY_GENRE")).map(uncounted)
        details += [
            album.label.map { Fact("Label", $0) },
            fact("Catalogue No.", tags.values("CATALOGNUMBER").joined(separator: ", ")),
            format.map { Fact("Format", $0) },
            tags.first("RELEASECOUNTRY").map { Fact("Country", Self.country($0, locale: locale)) },
            fact(
                languages.count == 1 ? "Language" : "Languages", languages.joined(separator: ", ")),
            fact("Barcode", tags.values("BARCODE").joined(separator: ", ")),
            fact("RYM Genres", genres.joined(separator: ", ")),
            fact("Scene", tags.values("RYM_SCENE").map(uncounted).joined(separator: ", ")),
            fact("Descriptors", tags.values("RYM_DESCRIPTORS").joined(separator: ", ")),
        ]
        self.details = details.compactMap(\.self).filter { !$0.value.isEmpty }
        if let score = album.rating {
            let votes = tags.first("RYM_RATING_VOTES").flatMap { Int($0) }
            rating = [
                score.formatted(.number.precision(.fractionLength(2)).locale(locale)),
                votes.map {
                    $0 == 1 ? "1 rating" : "\($0.formatted(.number.locale(locale))) ratings"
                },
            ].compactMap(\.self).joined(separator: " · ")
        }
        rank = tags.first("RYM_RANK")
        fetched = tags.first("RYM_FETCHED_AT").map(date)
        rymURL = tags.first("RYM_URL").flatMap(URL.init(string:))
    }

    static func date(_ value: String, locale: Locale) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt, year: parts.first,
            month: parts.count > 1 ? parts[1] : 1, day: parts.count > 2 ? parts[2] : 1)
        components.calendar?.timeZone = .gmt
        guard parts.count > 1, let day = components.date else { return value }
        let style = Date.FormatStyle(locale: locale, timeZone: .gmt)
        return parts.count > 2
            ? day.formatted(style.day().month(.abbreviated).year())
            : day.formatted(style.month(.abbreviated).year())
    }

    static func country(_ code: String, locale: Locale) -> String {
        switch code {
        case "XW": "Worldwide"
        case "XE": "Europe"
        default: locale.localizedString(forRegionCode: code) ?? code
        }
    }
}

private func fact(_ label: String, _ value: String) -> Fact? {
    value.isEmpty ? nil : Fact(label, value)
}

func capitalised(_ value: String) -> String {
    value.prefix(1).uppercased() + value.dropFirst()
}

func uncounted(_ value: String) -> String {
    value.replacing(/\s*\(\d+\)$/, with: "")
}

public struct PersonCredit: Sendable, Equatable, Identifiable {
    public var name: String
    public var text: String
    public var id: String { name }
}

public func creditSummary(_ credits: [Credit], tracks: [Track]) -> [PersonCredit] {
    let order = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($1.id, $0) })
    let sorted = credits.filter { order[$0.trackId] != nil }.sorted {
        (order[$0.trackId]!, $0.position) < (order[$1.trackId]!, $1.position)
    }
    var names: [String] = []
    var reads: [String: [(read: String, tracks: Set<Int>)]] = [:]
    for credit in sorted {
        let track = order[credit.trackId]!
        if reads[credit.name] == nil { names.append(credit.name) }
        var list = reads[credit.name, default: []]
        if let i = list.firstIndex(where: { $0.read == credit.reads }) {
            list[i].tracks.insert(track)
        } else {
            list.append((credit.reads, [track]))
        }
        reads[credit.name] = list
    }
    let labels = trackLabels(tracks)
    let count = { (name: String) in reads[name]!.reduce(Set<Int>()) { $0.union($1.tracks) }.count }
    return names.enumerated()
        .sorted { (-count($0.element), $0.offset) < (-count($1.element), $1.offset) }
        .map { _, name in
            var groups: [(reads: [String], tracks: Set<Int>)] = []
            for (read, tracks) in reads[name]! {
                if let i = groups.firstIndex(where: { $0.tracks == tracks }) {
                    groups[i].reads.append(read)
                } else {
                    groups.append(([read], tracks))
                }
            }
            let text = groups.map { group in
                let reads = group.reads.joined(separator: ", ")
                if tracks.count == 1 { return reads }
                if group.tracks.count == tracks.count { return "\(reads) (all tracks)" }
                return "\(reads) (\(ranges(group.tracks.sorted(), tracks: tracks, labels: labels)))"
            }
            .joined(separator: ", ")
            return PersonCredit(name: name, text: capitalised(text))
        }
}

func trackLabels(_ tracks: [Track]) -> [String] {
    let discs = Set(tracks.map { $0.disc ?? 1 }).count
    return tracks.enumerated().map { index, track in
        let number = track.number.map(String.init) ?? String(index + 1)
        return discs > 1 ? "\(track.disc ?? 1).\(number)" : number
    }
}

func ranges(_ indices: [Int], tracks: [Track], labels: [String]) -> String {
    var parts: [String] = []
    var start = indices[0]
    var end = start
    for index in indices.dropFirst() + [Int.max] {
        if index == end + 1, tracks[index].disc == tracks[end].disc {
            end = index
            continue
        }
        parts.append(
            start == end
                ? labels[start]
                : "\(labels[start])\(end == start + 1 ? ", " : "–")\(labels[end])")
        start = index
        end = index
    }
    return parts.joined(separator: ", ")
}
