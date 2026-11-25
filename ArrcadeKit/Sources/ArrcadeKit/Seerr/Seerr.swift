import Foundation

/// Media availability status as reported by Overseerr/Jellyseerr/Seerr.
public enum SeerrMediaStatus: Int, Codable, Sendable {
    case unknown = 1, pending = 2, processing = 3, partiallyAvailable = 4, available = 5, blocklisted = 6, deleted = 7

    public var label: String {
        switch self {
        case .unknown: "Not Requested"
        case .pending: "Pending"
        case .processing: "Requested"
        case .partiallyAvailable: "Partially Available"
        case .available: "Available"
        case .blocklisted: "Blocklisted"
        case .deleted: "Deleted"
        }
    }
}

public enum SeerrRequestStatus: Int, Codable, Sendable {
    case pending = 1, approved = 2, declined = 3, failed = 4, completed = 5
    public var label: String {
        switch self {
        case .pending: "Pending Approval"
        case .approved: "Approved"
        case .declined: "Declined"
        case .failed: "Failed"
        case .completed: "Completed"
        }
    }
}

public enum SeerrRequestFilter: String, CaseIterable, Sendable, Identifiable {
    case all, pending, approved, processing, available, unavailable, failed, completed, deleted
    public var id: String { rawValue }
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public struct SeerrPageInfo: Codable, Sendable, Hashable {
    public var pages: Int
    public var pageSize: Int
    public var results: Int
    public var page: Int
}

public struct SeerrUser: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var email: String?
    public var displayName: String?
    public var username: String?
    public var plexUsername: String?
    public var jellyfinUsername: String?
    public var avatar: String?
    public var permissions: Int?
    public var requestCount: Int?
    public var userType: Int?
    public var name: String { displayName ?? username ?? plexUsername ?? jellyfinUsername ?? email ?? "User \(id)" }
    /// Admin (2) or Manage Requests (16)
    public var canManageRequests: Bool { ((permissions ?? 0) & 2) != 0 || ((permissions ?? 0) & 16) != 0 }
}

public struct SeerrDownloadStatus: Codable, Sendable, Hashable {
    public var externalId: Int?
    public var estimatedCompletionTime: Date?
    public var mediaType: String?
    public var size: Int64?
    public var sizeLeft: Int64?
    public var status: String?
    public var timeLeft: String?
    public var title: String?
}

public struct SeerrSeasonStatus: Codable, Sendable, Hashable {
    public var id: Int?
    public var seasonNumber: Int
    public var status: Int?
    public var status4k: Int?
}

public struct SeerrMediaInfo: Codable, Sendable, Hashable {
    public var id: Int
    public var mediaType: String?
    public var tmdbId: Int?
    public var tvdbId: Int?
    public var status: SeerrMediaStatus?
    public var status4k: SeerrMediaStatus?
    public var downloadStatus: [SeerrDownloadStatus]?
    public var seasons: [SeerrSeasonStatus]?
    public var requests: [SeerrRequest]?
    public var serviceUrl: String?
    public var mediaUrl: String?
    public var externalServiceId: Int?
    public var createdAt: Date?
    public var mediaAddedAt: Date?
}

public struct SeerrRequestSeason: Codable, Sendable, Hashable {
    public var id: Int?
    public var seasonNumber: Int
    public var status: Int?
}

public struct SeerrRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var status: SeerrRequestStatus?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var type: String?
    public var is4k: Bool?
    public var serverId: Int?
    public var profileId: Int?
    public var rootFolder: String?
    public var media: SeerrMediaInfo?
    public var seasons: [SeerrRequestSeason]?
    public var requestedBy: SeerrUser?
    public var modifiedBy: SeerrUser?
    public var seasonCount: Int?
    public var isAutoRequest: Bool?
    public var canRemove: Bool?

    public var isMovie: Bool { (type ?? media?.mediaType) == "movie" }
    public var tmdbId: Int? { media?.tmdbId }
}

public struct SeerrPagedRequests: Codable, Sendable, Hashable {
    public var pageInfo: SeerrPageInfo
    public var results: [SeerrRequest]
}

public struct SeerrRequestCount: Codable, Sendable, Hashable {
    public var total: Int?
    public var movie: Int?
    public var tv: Int?
    public var pending: Int?
    public var approved: Int?
    public var declined: Int?
    public var processing: Int?
    public var available: Int?
    public var completed: Int?
}

public struct SeerrGenre: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}

/// Item in discover / search pages (movie, tv or person).
public struct SeerrMediaResult: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var mediaType: String?
    public var title: String?
    public var name: String?
    public var originalTitle: String?
    public var originalName: String?
    public var releaseDate: String?
    public var firstAirDate: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var profilePath: String?
    public var overview: String?
    public var voteAverage: Double?
    public var voteCount: Int?
    public var popularity: Double?
    public var genreIds: [Int]?
    public var mediaInfo: SeerrMediaInfo?

    public var displayTitle: String { title ?? name ?? originalTitle ?? originalName ?? "Untitled" }
    public var year: String? {
        let d = releaseDate ?? firstAirDate
        guard let d, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
    public var isMovie: Bool { mediaType == "movie" }
    public var isTV: Bool { mediaType == "tv" }
    public var isPerson: Bool { mediaType == "person" }
    public var uid: String { "\(mediaType ?? "x")-\(id)" }
}

public struct SeerrDiscoverPage: Codable, Sendable, Hashable {
    public var page: Int
    public var totalPages: Int
    public var totalResults: Int
    public var results: [SeerrMediaResult]
}

public struct SeerrCast: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var character: String?
    public var profilePath: String?
    public var creditId: String?
}

public struct SeerrCredits: Codable, Sendable, Hashable {
    public var cast: [SeerrCast]?
}

public struct SeerrVideo: Codable, Sendable, Hashable {
    public var url: String?
    public var key: String?
    public var name: String?
    public var site: String?
    public var type: String?
}

public struct SeerrNetwork: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}

public struct SeerrSeason: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var name: String?
    public var episodeCount: Int?
    public var airDate: String?
    public var posterPath: String?
    public var overview: String?
}

/// Combined details for movie or tv.
public struct SeerrMediaDetails: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String?
    public var name: String?
    public var originalTitle: String?
    public var overview: String?
    public var tagline: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var releaseDate: String?
    public var firstAirDate: String?
    public var runtime: Int?
    public var episodeRunTime: [Int]?
    public var status: String?
    public var genres: [SeerrGenre]?
    public var voteAverage: Double?
    public var voteCount: Int?
    public var mediaInfo: SeerrMediaInfo?
    public var credits: SeerrCredits?
    public var relatedVideos: [SeerrVideo]?
    public var seasons: [SeerrSeason]?
    public var numberOfSeasons: Int?
    public var numberOfEpisodes: Int?
    public var networks: [SeerrNetwork]?
    public var imdbId: String?
    public var homepage: String?

    public var displayTitle: String { title ?? name ?? originalTitle ?? "Untitled" }
    public var year: String? {
        let d = releaseDate ?? firstAirDate
        guard let d, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
    public var trailerURL: URL? {
        relatedVideos?.first(where: { $0.type == "Trailer" && $0.site == "YouTube" })?.url.flatMap(URL.init(string:))
    }
    public var requestableSeasons: [SeerrSeason] { (seasons ?? []).filter { $0.seasonNumber > 0 } }
}

public struct SeerrServiceServer: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var is4k: Bool
    public var isDefault: Bool
    public var activeDirectory: String?
    public var activeProfileId: Int?
    public var activeTags: [Int]?
}

public struct SeerrServiceProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}

public struct SeerrServiceRootFolder: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var path: String
    public var freeSpace: Int64?
}

public struct SeerrServiceDetails: Codable, Sendable, Hashable {
    public var server: SeerrServiceServer
    public var profiles: [SeerrServiceProfile]
    public var rootFolders: [SeerrServiceRootFolder]
}

public struct SeerrIssueComment: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var message: String
    public var user: SeerrUser?
    public var createdAt: Date?
}

public struct SeerrIssue: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var issueType: Int
    public var status: Int
    public var problemSeason: Int?
    public var problemEpisode: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var media: SeerrMediaInfo?
    public var createdBy: SeerrUser?
    public var comments: [SeerrIssueComment]?

    public var typeLabel: String {
        switch issueType { case 1: "Video"; case 2: "Audio"; case 3: "Subtitles"; default: "Other" }
    }
    public var isOpen: Bool { status == 1 }
}

public struct SeerrPagedIssues: Codable, Sendable, Hashable {
    public var pageInfo: SeerrPageInfo
    public var results: [SeerrIssue]
}

public struct SeerrStatus: Codable, Sendable, Hashable {
    public var version: String
    public var commitTag: String?
    public var updateAvailable: Bool?
    public var commitsBehind: Int?
    public var restartRequired: Bool?
}

public enum SeerrDiscoverCategory: String, CaseIterable, Sendable, Identifiable {
    case trending, popularMovies, upcomingMovies, popularTV, upcomingTV
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .trending: "Trending"
        case .popularMovies: "Popular Movies"
        case .upcomingMovies: "Upcoming Movies"
        case .popularTV: "Popular Series"
        case .upcomingTV: "Upcoming Series"
        }
    }
    var path: String {
        switch self {
        case .trending: "discover/trending"
        case .popularMovies: "discover/movies"
        case .upcomingMovies: "discover/movies/upcoming"
        case .popularTV: "discover/tv"
        case .upcomingTV: "discover/tv/upcoming"
        }
    }
}

public final class SeerrClient: Sendable {
    public let http: HTTPClient

    public init(config: ServiceConfig) {
        http = HTTPClient(config: config, authHeaders: ["X-Api-Key": config.apiKey])
    }

    private func p(_ path: String) -> String { "/api/v1/" + path }

    func get<T: Decodable>(_ t: T.Type, _ path: String, _ q: [(String, String)] = []) async throws -> T {
        try await http.decode(T.self, .get, p(path), query: q)
    }

    @discardableResult
    func post(_ path: String, _ body: JSONValue = [:]) async throws -> Data {
        try await http.send(.post, p(path), body: try .encode(body)).0
    }

    public func status() async throws -> SeerrStatus { try await get(SeerrStatus.self, "status") }
    public func me() async throws -> SeerrUser { try await get(SeerrUser.self, "auth/me") }

    public func discover(_ category: SeerrDiscoverCategory, page: Int = 1) async throws -> SeerrDiscoverPage {
        try await get(SeerrDiscoverPage.self, category.path, [("page", "\(page)"), ("language", "en")])
    }

    public func search(_ query: String, page: Int = 1) async throws -> SeerrDiscoverPage {
        try await get(SeerrDiscoverPage.self, "search", [("query", query), ("page", "\(page)"), ("language", "en")])
    }

    public func movie(tmdbId: Int) async throws -> SeerrMediaDetails { try await get(SeerrMediaDetails.self, "movie/\(tmdbId)") }
    public func tv(tmdbId: Int) async throws -> SeerrMediaDetails { try await get(SeerrMediaDetails.self, "tv/\(tmdbId)") }

    public func details(tmdbId: Int, isMovie: Bool) async throws -> SeerrMediaDetails {
        isMovie ? try await movie(tmdbId: tmdbId) : try await tv(tmdbId: tmdbId)
    }

    public func recommendations(tmdbId: Int, isMovie: Bool) async throws -> SeerrDiscoverPage {
        try await get(SeerrDiscoverPage.self, "\(isMovie ? "movie" : "tv")/\(tmdbId)/recommendations", [("page", "1")])
    }

    // MARK: Requests

    public func requests(filter: SeerrRequestFilter = .all, take: Int = 30, skip: Int = 0, sort: String = "added") async throws -> SeerrPagedRequests {
        try await get(SeerrPagedRequests.self, "request", [("take", "\(take)"), ("skip", "\(skip)"), ("filter", filter.rawValue), ("sort", sort)])
    }

    public func requestCount() async throws -> SeerrRequestCount { try await get(SeerrRequestCount.self, "request/count") }

    public func approve(requestId: Int) async throws { try await post("request/\(requestId)/approve") }
    public func decline(requestId: Int) async throws { try await post("request/\(requestId)/decline") }
    public func retry(requestId: Int) async throws { try await post("request/\(requestId)/retry") }
    public func deleteRequest(id: Int) async throws { try await http.send(.delete, p("request/\(id)")) }

    /// Create a request. `seasons` is ignored for movies; empty means all seasons for TV.
    @discardableResult
    public func request(tmdbId: Int, isMovie: Bool, seasons: [Int] = [], is4k: Bool = false,
                        serverId: Int? = nil, profileId: Int? = nil, rootFolder: String? = nil) async throws -> SeerrRequest {
        var body: [String: JSONValue] = [
            "mediaType": .string(isMovie ? "movie" : "tv"),
            "mediaId": JSONValue(tmdbId),
            "is4k": .bool(is4k)
        ]
        if !isMovie { body["seasons"] = seasons.isEmpty ? "all" : JSONValue(seasons) }
        if let serverId { body["serverId"] = JSONValue(serverId) }
        if let profileId { body["profileId"] = JSONValue(profileId) }
        if let rootFolder { body["rootFolder"] = .string(rootFolder) }
        let data = try await post("request", .object(body))
        return try HTTPClient.decode(SeerrRequest.self, from: data, path: "request")
    }

    // MARK: Services

    public func radarrServers() async throws -> [SeerrServiceServer] { try await get([SeerrServiceServer].self, "service/radarr") }
    public func sonarrServers() async throws -> [SeerrServiceServer] { try await get([SeerrServiceServer].self, "service/sonarr") }
    public func serviceDetails(isMovie: Bool, serverId: Int) async throws -> SeerrServiceDetails {
        try await get(SeerrServiceDetails.self, "service/\(isMovie ? "radarr" : "sonarr")/\(serverId)")
    }

    // MARK: Issues

    public func issues(filter: String = "open", take: Int = 30, skip: Int = 0) async throws -> SeerrPagedIssues {
        try await get(SeerrPagedIssues.self, "issue", [("take", "\(take)"), ("skip", "\(skip)"), ("filter", filter), ("sort", "added")])
    }
    public func issue(id: Int) async throws -> SeerrIssue { try await get(SeerrIssue.self, "issue/\(id)") }
    public func setIssue(id: Int, resolved: Bool) async throws { try await post("issue/\(id)/\(resolved ? "resolved" : "open")") }
    public func comment(issueId: Int, message: String) async throws { try await post("issue/\(issueId)/comment", ["message": .string(message)]) }
    public func deleteIssue(id: Int) async throws { try await http.send(.delete, p("issue/\(id)")) }
    public func createIssue(mediaId: Int, issueType: Int, message: String, season: Int = 0, episode: Int = 0) async throws {
        try await post("issue", [
            "mediaId": JSONValue(mediaId), "issueType": JSONValue(issueType), "message": .string(message),
            "problemSeason": JSONValue(season), "problemEpisode": JSONValue(episode)
        ])
    }

    // MARK: Images (TMDB)

    public static func imageURL(_ path: String?, size: String = "w342") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}
