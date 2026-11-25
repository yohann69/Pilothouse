import Foundation

public struct SonarrRatings: Codable, Sendable, Hashable {
    public var votes: Int?
    public var value: Double?
}

public struct SonarrSeasonStatistics: Codable, Sendable, Hashable {
    public var episodeFileCount: Int?
    public var episodeCount: Int?
    public var totalEpisodeCount: Int?
    public var sizeOnDisk: Int64?
    public var percentOfEpisodes: Double?
    public var nextAiring: Date?
    public var previousAiring: Date?
}

public struct SonarrSeason: Codable, Sendable, Hashable, Identifiable {
    public var seasonNumber: Int
    public var monitored: Bool
    public var statistics: SonarrSeasonStatistics?
    public var id: Int { seasonNumber }
}

public struct SonarrSeriesStatistics: Codable, Sendable, Hashable {
    public var seasonCount: Int?
    public var episodeFileCount: Int?
    public var episodeCount: Int?
    public var totalEpisodeCount: Int?
    public var sizeOnDisk: Int64?
    public var percentOfEpisodes: Double?
}

public struct SonarrSeries: Codable, Sendable, Hashable, Identifiable {
    public var id: Int?
    public var title: String
    public var sortTitle: String?
    public var status: String?
    public var ended: Bool?
    public var overview: String?
    public var network: String?
    public var airTime: String?
    public var images: [ArrImage]?
    public var originalLanguage: ArrLanguage?
    public var remotePoster: String?
    public var seasons: [SonarrSeason]?
    public var year: Int?
    public var path: String?
    public var qualityProfileId: Int?
    public var seasonFolder: Bool?
    public var monitored: Bool?
    public var monitorNewItems: String?
    public var useSceneNumbering: Bool?
    public var runtime: Int?
    public var tvdbId: Int?
    public var tvRageId: Int?
    public var tvMazeId: Int?
    public var tmdbId: Int?
    public var firstAired: Date?
    public var lastAired: Date?
    public var seriesType: String?
    public var cleanTitle: String?
    public var imdbId: String?
    public var titleSlug: String?
    public var rootFolderPath: String?
    public var certification: String?
    public var genres: [String]?
    public var tags: [Int]?
    public var added: Date?
    public var ratings: SonarrRatings?
    public var statistics: SonarrSeriesStatistics?
    public var nextAiring: Date?
    public var previousAiring: Date?

    public var stableID: Int { id ?? -(tvdbId ?? 0) }
    public var isInLibrary: Bool { (id ?? 0) > 0 }
    public var percent: Double { (statistics?.percentOfEpisodes ?? 0) / 100 }
    public var episodeSummary: String {
        "\(statistics?.episodeFileCount ?? 0)/\(statistics?.episodeCount ?? 0)"
    }
    public var isContinuing: Bool { (status ?? "").lowercased() == "continuing" }
}

public struct SonarrEpisode: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var seriesId: Int
    public var tvdbId: Int?
    public var episodeFileId: Int?
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var title: String?
    public var airDate: String?
    public var airDateUtc: Date?
    public var lastSearchTime: Date?
    public var runtime: Int?
    public var finaleType: String?
    public var overview: String?
    public var hasFile: Bool?
    public var monitored: Bool
    public var absoluteEpisodeNumber: Int?
    public var unverifiedSceneNumbering: Bool?
    public var series: SonarrSeries?
    public var images: [ArrImage]?

    public var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
    public var aired: Bool { (airDateUtc ?? .distantFuture) < Date() }
}

public struct SonarrEpisodeFile: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var seriesId: Int?
    public var seasonNumber: Int?
    public var relativePath: String?
    public var path: String?
    public var size: Int64?
    public var dateAdded: Date?
    public var sceneName: String?
    public var releaseGroup: String?
    public var languages: [ArrLanguage]?
    public var quality: ArrQuality?
    public var customFormats: [ArrCustomFormat]?
    public var customFormatScore: Int?
    public var mediaInfo: ArrMediaInfo?
    public var qualityCutoffNotMet: Bool?
}

public final class SonarrClient: ArrClient, @unchecked Sendable {
    public init(config: ServiceConfig) { super.init(config: config, apiVersion: "v3") }

    // MARK: Series

    public func series() async throws -> [SonarrSeries] { try await get([SonarrSeries].self, "series") }
    public func series(id: Int) async throws -> SonarrSeries { try await get(SonarrSeries.self, "series/\(id)") }
    public func rawSeries(id: Int) async throws -> JSONValue { try await raw("series/\(id)") }

    public func lookup(term: String) async throws -> [SonarrSeries] {
        try await get([SonarrSeries].self, "series/lookup", query: [("term", term)])
    }
    public func rawLookup(term: String) async throws -> [JSONValue] {
        try await get([JSONValue].self, "series/lookup", query: [("term", term)])
    }

    @discardableResult
    public func add(lookup: JSONValue, qualityProfileId: Int, rootFolderPath: String, monitor: SonarrMonitorOption,
                    seriesType: String, seasonFolder: Bool, tags: [Int], searchForMissing: Bool,
                    searchForCutoffUnmet: Bool = false) async throws -> SonarrSeries {
        var body = lookup
        body["qualityProfileId"] = JSONValue(qualityProfileId)
        body["rootFolderPath"] = .string(rootFolderPath)
        body["monitored"] = .bool(monitor != .none)
        body["seriesType"] = .string(seriesType)
        body["seasonFolder"] = .bool(seasonFolder)
        body["tags"] = JSONValue(tags)
        body["addOptions"] = [
            "monitor": .string(monitor.rawValue),
            "searchForMissingEpisodes": .bool(searchForMissing),
            "searchForCutoffUnmetEpisodes": .bool(searchForCutoffUnmet)
        ]
        body["id"] = nil
        return try await post("series", body).decode(SonarrSeries.self)
    }

    @discardableResult
    public func update(seriesId: Int, moveFiles: Bool = false, _ mutate: @Sendable (inout JSONValue) -> Void) async throws -> SonarrSeries {
        var raw = try await rawSeries(id: seriesId)
        mutate(&raw)
        return try await put("series/\(seriesId)", raw, query: [("moveFiles", "\(moveFiles)")]).decode(SonarrSeries.self)
    }

    public func setSeasonMonitored(seriesId: Int, seasonNumber: Int, monitored: Bool) async throws {
        try await update(seriesId: seriesId) { raw in
            guard case .array(var seasons)? = raw["seasons"] else { return }
            for i in seasons.indices where seasons[i]["seasonNumber"]?.intValue == seasonNumber {
                seasons[i]["monitored"] = .bool(monitored)
            }
            raw["seasons"] = .array(seasons)
        }
    }

    public func deleteSeries(id: Int, deleteFiles: Bool, addExclusion: Bool) async throws {
        try await delete("series/\(id)", query: [("deleteFiles", "\(deleteFiles)"), ("addImportListExclusion", "\(addExclusion)")])
    }

    // MARK: Episodes

    public func episodes(seriesId: Int, seasonNumber: Int? = nil) async throws -> [SonarrEpisode] {
        var q: [(String, String)] = [("seriesId", "\(seriesId)"), ("includeImages", "false")]
        if let seasonNumber { q.append(("seasonNumber", "\(seasonNumber)")) }
        return try await get([SonarrEpisode].self, "episode", query: q)
    }

    public func episode(id: Int) async throws -> SonarrEpisode { try await get(SonarrEpisode.self, "episode/\(id)") }

    public func setEpisodesMonitored(ids: [Int], monitored: Bool) async throws {
        try await put("episode/monitor", ["episodeIds": JSONValue(ids), "monitored": .bool(monitored)])
    }

    public func episodeFiles(seriesId: Int) async throws -> [SonarrEpisodeFile] {
        try await get([SonarrEpisodeFile].self, "episodefile", query: [("seriesId", "\(seriesId)")])
    }
    public func deleteEpisodeFile(id: Int) async throws { try await delete("episodefile/\(id)") }

    // MARK: History / queue / calendar / wanted

    public func history(seriesId: Int, seasonNumber: Int? = nil) async throws -> [ArrHistoryRecord] {
        var q: [(String, String)] = [("seriesId", "\(seriesId)"), ("includeEpisode", "true")]
        if let seasonNumber { q.append(("seasonNumber", "\(seasonNumber)")) }
        return try await get([ArrHistoryRecord].self, "history/series", query: q)
    }

    public func history(episodeId: Int) async throws -> ArrPage<ArrHistoryRecord> {
        try await get(ArrPage<ArrHistoryRecord>.self, "history", query: [
            ("episodeId", "\(episodeId)"), ("page", "1"), ("pageSize", "50"), ("sortKey", "date"), ("sortDirection", "descending")
        ])
    }

    public func history(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<ArrHistoryRecord> {
        try await get(ArrPage<ArrHistoryRecord>.self, "history", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "date"), ("sortDirection", "descending"),
            ("includeSeries", "true"), ("includeEpisode", "true")
        ])
    }

    public func queue(page: Int = 1, pageSize: Int = 200) async throws -> ArrPage<ArrQueueItem> {
        try await get(ArrPage<ArrQueueItem>.self, "queue", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("includeSeries", "true"), ("includeEpisode", "true"),
            ("includeUnknownSeriesItems", "true")
        ])
    }

    public func calendar(start: Date, end: Date, unmonitored: Bool = true) async throws -> [SonarrEpisode] {
        try await get([SonarrEpisode].self, "calendar", query: [
            ("start", start.formatted(.iso8601)), ("end", end.formatted(.iso8601)),
            ("unmonitored", "\(unmonitored)"), ("includeSeries", "true"), ("includeEpisodeFile", "false"), ("includeEpisodeImages", "false")
        ])
    }

    public func wantedMissing(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<SonarrEpisode> {
        try await get(ArrPage<SonarrEpisode>.self, "wanted/missing", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "episodes.airDateUtc"), ("sortDirection", "descending"),
            ("includeSeries", "true"), ("monitored", "true")
        ])
    }

    public func wantedCutoff(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<SonarrEpisode> {
        try await get(ArrPage<SonarrEpisode>.self, "wanted/cutoff", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "episodes.airDateUtc"), ("sortDirection", "descending"),
            ("includeSeries", "true"), ("monitored", "true")
        ])
    }

    // MARK: Search / commands

    public func releases(episodeId: Int) async throws -> [ArrRelease] { try await releases(query: [("episodeId", "\(episodeId)")]) }
    public func releases(seriesId: Int, seasonNumber: Int) async throws -> [ArrRelease] {
        try await releases(query: [("seriesId", "\(seriesId)"), ("seasonNumber", "\(seasonNumber)")])
    }

    public func searchSeries(id: Int) async throws { try await command("SeriesSearch", ["seriesId": JSONValue(id)]) }
    public func searchSeason(seriesId: Int, seasonNumber: Int) async throws {
        try await command("SeasonSearch", ["seriesId": JSONValue(seriesId), "seasonNumber": JSONValue(seasonNumber)])
    }
    public func searchEpisodes(ids: [Int]) async throws { try await command("EpisodeSearch", ["episodeIds": JSONValue(ids)]) }
    public func refreshSeries(id: Int) async throws { try await command("RefreshSeries", ["seriesId": JSONValue(id)]) }
    public func rescanSeries(id: Int) async throws { try await command("RescanSeries", ["seriesId": JSONValue(id)]) }
    public func renameSeries(ids: [Int]) async throws { try await command("RenameSeries", ["seriesIds": JSONValue(ids)]) }

    public func imageURL(_ image: ArrImage?, width: Int? = nil) -> URL? {
        posterURL(image, http: http, width: width)
    }
}
