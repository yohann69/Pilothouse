import Foundation

public struct ProwlarrCategory: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var subCategories: [ProwlarrCategory]?
}

public struct ProwlarrCapabilities: Codable, Sendable, Hashable {
    public var categories: [ProwlarrCategory]?
    public var limitsMax: Int?
    public var limitsDefault: Int?
}

public struct ProwlarrIndexer: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var definitionName: String?
    public var description: String?
    public var language: String?
    public var enable: Bool
    public var redirect: Bool?
    public var supportsRss: Bool?
    public var supportsSearch: Bool?
    public var appProfileId: Int?
    public var `protocol`: String?
    public var privacy: String?
    public var priority: Int?
    public var tags: [Int]?
    public var added: Date?
    public var indexerUrls: [String]?
    public var implementation: String?
    public var capabilities: ProwlarrCapabilities?
    public var displayName: String { name ?? definitionName ?? "Indexer \(id)" }
}

public struct ProwlarrIndexerStat: Codable, Sendable, Hashable, Identifiable {
    public var indexerId: Int
    public var indexerName: String?
    public var averageResponseTime: Int?
    public var averageGrabResponseTime: Int?
    public var numberOfQueries: Int?
    public var numberOfGrabs: Int?
    public var numberOfRssQueries: Int?
    public var numberOfAuthQueries: Int?
    public var numberOfFailedQueries: Int?
    public var numberOfFailedGrabs: Int?
    public var numberOfFailedRssQueries: Int?
    public var numberOfFailedAuthQueries: Int?
    public var id: Int { indexerId }
}

public struct ProwlarrIndexerStats: Codable, Sendable, Hashable {
    public var indexers: [ProwlarrIndexerStat]?
}

public struct ProwlarrIndexerStatus: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var indexerId: Int
    public var disabledTill: Date?
    public var mostRecentFailure: Date?
    public var initialFailure: Date?
}

public struct ProwlarrSearchResult: Codable, Sendable, Hashable, Identifiable {
    public var guid: String
    public var age: Int?
    public var ageHours: Double?
    public var ageMinutes: Double?
    public var size: Int64?
    public var files: Int?
    public var grabs: Int?
    public var indexerId: Int
    public var indexer: String?
    public var title: String
    public var sortTitle: String?
    public var imdbId: Int?
    public var tmdbId: Int?
    public var tvdbId: Int?
    public var publishDate: Date?
    public var downloadUrl: String?
    public var magnetUrl: String?
    public var infoUrl: String?
    public var infoHash: String?
    public var categories: [ProwlarrCategory]?
    public var seeders: Int?
    public var leechers: Int?
    public var `protocol`: String?
    public var fileName: String?
    public var posterUrl: String?

    public var id: String { "\(indexerId)|\(guid)" }
    public var isTorrent: Bool { `protocol`?.lowercased() == "torrent" }
    public var categoryNames: String {
        (categories ?? []).compactMap(\.name).joined(separator: ", ")
    }
}

public struct ProwlarrApplication: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var syncLevel: String?
    public var implementation: String?
    public var enable: Bool?
}

public struct ProwlarrDownloadClient: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var enable: Bool?
    public var `protocol`: String?
    public var implementation: String?
    public var priority: Int?
}

public struct ProwlarrHistoryRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var indexerId: Int?
    public var date: Date
    public var downloadId: String?
    public var successful: Bool?
    public var eventType: String?
    public var data: [String: String?]?
    public func value(_ key: String) -> String? { data?[key] ?? nil }
}

public enum ProwlarrSearchType: String, CaseIterable, Sendable, Identifiable {
    case search, movie = "movie", tv = "tvsearch", music, book
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .search: "All"
        case .movie: "Movies"
        case .tv: "TV"
        case .music: "Music"
        case .book: "Books"
        }
    }
    /// Newznab parent category to restrict to.
    public var defaultCategories: [Int] {
        switch self {
        case .search: []
        case .movie: [2000]
        case .tv: [5000]
        case .music: [3000]
        case .book: [7000]
        }
    }
}

public final class ProwlarrClient: ArrClient, @unchecked Sendable {
    public init(config: ServiceConfig) { super.init(config: config, apiVersion: "v1") }

    public func indexers() async throws -> [ProwlarrIndexer] { try await get([ProwlarrIndexer].self, "indexer") }
    public func indexerStats() async throws -> ProwlarrIndexerStats { try await get(ProwlarrIndexerStats.self, "indexerstats") }
    public func indexerStatuses() async throws -> [ProwlarrIndexerStatus] { try await get([ProwlarrIndexerStatus].self, "indexerstatus") }
    public func applications() async throws -> [ProwlarrApplication] { try await get([ProwlarrApplication].self, "applications") }
    public func downloadClients() async throws -> [ProwlarrDownloadClient] { try await get([ProwlarrDownloadClient].self, "downloadclient") }

    public func setIndexer(id: Int, enabled: Bool) async throws {
        var raw = try await raw("indexer/\(id)")
        raw["enable"] = .bool(enabled)
        try await put("indexer/\(id)", raw)
    }

    public func setIndexerPriority(id: Int, priority: Int) async throws {
        var raw = try await raw("indexer/\(id)")
        raw["priority"] = JSONValue(priority)
        try await put("indexer/\(id)", raw)
    }

    /// Runs Prowlarr's test for one indexer. Throws with the server's validation message on failure.
    public func testIndexer(id: Int) async throws {
        let raw = try await raw("indexer/\(id)")
        try await post("indexer/test", raw)
    }

    public func testAllIndexers() async throws -> JSONValue { try await post("indexer/testall", [:]) }

    public func deleteIndexer(id: Int) async throws { try await delete("indexer/\(id)") }

    public func search(query: String, type: ProwlarrSearchType = .search, indexerIds: [Int] = [],
                       categories: [Int] = [], limit: Int = 100, offset: Int = 0) async throws -> [ProwlarrSearchResult] {
        var q: [(String, String)] = [("query", query), ("type", type.rawValue), ("limit", "\(limit)"), ("offset", "\(offset)")]
        for id in indexerIds { q.append(("indexerIds", "\(id)")) }
        for c in categories { q.append(("categories", "\(c)")) }
        return try await get([ProwlarrSearchResult].self, "search", query: q)
    }

    /// Ask Prowlarr to send the release to its configured download client.
    public func grab(_ result: ProwlarrSearchResult) async throws {
        try await post("search", ["guid": .string(result.guid), "indexerId": JSONValue(result.indexerId)])
    }

    public func history(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<ProwlarrHistoryRecord> {
        try await get(ArrPage<ProwlarrHistoryRecord>.self, "history", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "date"), ("sortDirection", "descending")
        ])
    }

    public func syncApplications() async throws { try await command("ApplicationIndexerSync") }
}
