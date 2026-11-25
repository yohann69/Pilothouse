import Foundation

public struct RadarrRating: Codable, Sendable, Hashable {
    public var votes: Int?
    public var value: Double?
}

public struct RadarrRatings: Codable, Sendable, Hashable {
    public var imdb: RadarrRating?
    public var tmdb: RadarrRating?
    public var metacritic: RadarrRating?
    public var rottenTomatoes: RadarrRating?
    public var trakt: RadarrRating?
}

public struct RadarrMovieFile: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var movieId: Int?
    public var relativePath: String?
    public var path: String?
    public var size: Int64?
    public var dateAdded: Date?
    public var sceneName: String?
    public var releaseGroup: String?
    public var edition: String?
    public var languages: [ArrLanguage]?
    public var quality: ArrQuality?
    public var customFormats: [ArrCustomFormat]?
    public var customFormatScore: Int?
    public var mediaInfo: ArrMediaInfo?
    public var qualityCutoffNotMet: Bool?
}

public struct RadarrCollection: Codable, Sendable, Hashable {
    public var title: String?
    public var tmdbId: Int?
}

public struct RadarrMovieStatistics: Codable, Sendable, Hashable {
    public var movieFileCount: Int?
    public var sizeOnDisk: Int64?
    public var releaseGroups: [String]?
}

public struct RadarrMovie: Codable, Sendable, Hashable, Identifiable {
    public var id: Int?
    public var title: String
    public var originalTitle: String?
    public var originalLanguage: ArrLanguage?
    public var sortTitle: String?
    public var sizeOnDisk: Int64?
    public var status: String?
    public var overview: String?
    public var inCinemas: Date?
    public var physicalRelease: Date?
    public var digitalRelease: Date?
    public var releaseDate: Date?
    public var images: [ArrImage]?
    public var website: String?
    public var year: Int?
    public var youTubeTrailerId: String?
    public var studio: String?
    public var path: String?
    public var qualityProfileId: Int?
    public var hasFile: Bool?
    public var movieFileId: Int?
    public var monitored: Bool?
    public var minimumAvailability: String?
    public var isAvailable: Bool?
    public var folderName: String?
    public var runtime: Int?
    public var cleanTitle: String?
    public var imdbId: String?
    public var tmdbId: Int
    public var titleSlug: String?
    public var rootFolderPath: String?
    public var certification: String?
    public var genres: [String]?
    public var tags: [Int]?
    public var added: Date?
    public var ratings: RadarrRatings?
    public var movieFile: RadarrMovieFile?
    public var collection: RadarrCollection?
    public var popularity: Double?
    public var statistics: RadarrMovieStatistics?
    public var remotePoster: String?

    public var stableID: Int { id ?? -tmdbId }
    public var isInLibrary: Bool { (id ?? 0) > 0 }
    public var fileSize: Int64 { sizeOnDisk ?? statistics?.sizeOnDisk ?? movieFile?.size ?? 0 }
    public var downloaded: Bool { hasFile ?? (movieFile != nil) }

    /// The best date to show as "release" for sorting.
    public var primaryRelease: Date? { digitalRelease ?? physicalRelease ?? inCinemas ?? releaseDate }

    public var statusLabel: String {
        if downloaded { return "Downloaded" }
        if monitored == false { return "Unmonitored" }
        if isAvailable == true { return "Missing" }
        return "Upcoming"
    }
}

public final class RadarrClient: ArrClient, @unchecked Sendable {
    public init(config: ServiceConfig) { super.init(config: config, apiVersion: "v3") }

    // MARK: Library

    public func movies() async throws -> [RadarrMovie] { try await get([RadarrMovie].self, "movie") }
    public func movie(id: Int) async throws -> RadarrMovie { try await get(RadarrMovie.self, "movie/\(id)") }
    public func rawMovie(id: Int) async throws -> JSONValue { try await raw("movie/\(id)") }

    public func lookup(term: String) async throws -> [RadarrMovie] {
        try await get([RadarrMovie].self, "movie/lookup", query: [("term", term)])
    }
    public func rawLookup(term: String) async throws -> [JSONValue] {
        try await get([JSONValue].self, "movie/lookup", query: [("term", term)])
    }
    public func lookup(tmdbId: Int) async throws -> JSONValue {
        try await raw("movie/lookup/tmdb", query: [("tmdbId", "\(tmdbId)")])
    }

    /// Add a movie from a lookup result.
    @discardableResult
    public func add(lookup: JSONValue, qualityProfileId: Int, rootFolderPath: String, monitored: Bool,
                    minimumAvailability: String, tags: [Int], searchForMovie: Bool) async throws -> RadarrMovie {
        var body = lookup
        body["qualityProfileId"] = JSONValue(qualityProfileId)
        body["rootFolderPath"] = .string(rootFolderPath)
        body["monitored"] = .bool(monitored)
        body["minimumAvailability"] = .string(minimumAvailability)
        body["tags"] = JSONValue(tags)
        body["addOptions"] = ["searchForMovie": .bool(searchForMovie), "monitor": monitored ? "movieOnly" : "none"]
        body["id"] = nil
        return try await post("movie", body).decode(RadarrMovie.self)
    }

    /// Edit arbitrary fields of a movie while preserving everything else.
    @discardableResult
    public func update(movieId: Int, moveFiles: Bool = false, _ mutate: @Sendable (inout JSONValue) -> Void) async throws -> RadarrMovie {
        var raw = try await rawMovie(id: movieId)
        mutate(&raw)
        return try await put("movie/\(movieId)", raw, query: [("moveFiles", "\(moveFiles)")]).decode(RadarrMovie.self)
    }

    public func setMonitored(movieIds: [Int], monitored: Bool) async throws {
        try await put("movie/editor", ["movieIds": JSONValue(movieIds), "monitored": .bool(monitored)])
    }

    public func deleteMovie(id: Int, deleteFiles: Bool, addExclusion: Bool) async throws {
        try await delete("movie/\(id)", query: [("deleteFiles", "\(deleteFiles)"), ("addImportExclusion", "\(addExclusion)")])
    }

    // MARK: Files / history

    public func movieFiles(movieId: Int) async throws -> [RadarrMovieFile] {
        try await get([RadarrMovieFile].self, "moviefile", query: [("movieId", "\(movieId)")])
    }
    public func deleteMovieFile(id: Int) async throws { try await delete("moviefile/\(id)") }

    public func history(movieId: Int) async throws -> [ArrHistoryRecord] {
        try await get([ArrHistoryRecord].self, "history/movie", query: [("movieId", "\(movieId)")])
    }

    public func history(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<ArrHistoryRecord> {
        try await get(ArrPage<ArrHistoryRecord>.self, "history", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "date"), ("sortDirection", "descending"), ("includeMovie", "true")
        ])
    }

    // MARK: Queue / calendar / wanted

    public func queue(page: Int = 1, pageSize: Int = 200) async throws -> ArrPage<ArrQueueItem> {
        try await get(ArrPage<ArrQueueItem>.self, "queue", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("includeMovie", "true"), ("includeUnknownMovieItems", "true")
        ])
    }

    public func calendar(start: Date, end: Date, unmonitored: Bool = true) async throws -> [RadarrMovie] {
        try await get([RadarrMovie].self, "calendar", query: [
            ("start", start.formatted(.iso8601)), ("end", end.formatted(.iso8601)), ("unmonitored", "\(unmonitored)")
        ])
    }

    public func wantedMissing(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<RadarrMovie> {
        try await get(ArrPage<RadarrMovie>.self, "wanted/missing", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "movieMetadata.sortTitle"), ("sortDirection", "ascending"), ("monitored", "true")
        ])
    }

    public func wantedCutoff(page: Int = 1, pageSize: Int = 50) async throws -> ArrPage<RadarrMovie> {
        try await get(ArrPage<RadarrMovie>.self, "wanted/cutoff", query: [
            ("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "movieMetadata.sortTitle"), ("sortDirection", "ascending"), ("monitored", "true")
        ])
    }

    // MARK: Search

    public func releases(movieId: Int) async throws -> [ArrRelease] {
        try await releases(query: [("movieId", "\(movieId)")])
    }

    public func grab(release: ArrRelease, movieId: Int) async throws {
        try await grab(release: release, extra: ["movieId": JSONValue(movieId)])
    }

    public func searchMovies(ids: [Int]) async throws { try await command("MoviesSearch", ["movieIds": JSONValue(ids)]) }
    public func refreshMovies(ids: [Int]) async throws { try await command("RefreshMovie", ["movieIds": JSONValue(ids)]) }
    public func rescanMovie(id: Int) async throws { try await command("RescanMovie", ["movieId": JSONValue(id)]) }
    public func renameMovies(ids: [Int]) async throws { try await command("RenameMovie", ["movieIds": JSONValue(ids)]) }

    /// Absolute URL for a library image (served by Radarr itself), sized.
    public func imageURL(_ image: ArrImage?, width: Int? = nil) -> URL? {
        posterURL(image, http: http, width: width)
    }
}

func posterURL(_ image: ArrImage?, http: HTTPClient, width: Int?) -> URL? {
    guard let image else { return nil }
    if let remote = image.remoteUrl, !remote.isEmpty {
        // TMDB: request a right-sized rendition instead of the original.
        if remote.contains("image.tmdb.org/t/p/original"), let width {
            let size = width <= 92 ? "w92" : width <= 154 ? "w154" : width <= 185 ? "w185" : width <= 342 ? "w342" : width <= 500 ? "w500" : width <= 780 ? "w780" : "w1280"
            return URL(string: remote.replacingOccurrences(of: "/t/p/original", with: "/t/p/\(size)"))
        }
        // TheTVDB: banners/posters have _t thumbnails
        return URL(string: remote)
    }
    if let path = image.url, !path.isEmpty {
        if path.hasPrefix("http") { return URL(string: path) }
        var p = path
        if let base = http.baseURL, let basePath = URL(string: base.absoluteString)?.path(), !basePath.isEmpty, basePath != "/", p.hasPrefix(basePath) {
            p = String(p.dropFirst(basePath.count))
        }
        var q: [(String, String)] = [("apikey", http.config.apiKey)]
        if let qIndex = p.firstIndex(of: "?") {
            let existing = p[p.index(after: qIndex)...]
            p = String(p[..<qIndex])
            for part in existing.split(separator: "&") {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { q.append((kv[0], kv[1].removingPercentEncoding ?? kv[1])) }
            }
        }
        return try? http.url(path: p, query: q)
    }
    return nil
}
