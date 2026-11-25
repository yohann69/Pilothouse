import Foundation

public struct ArrSystemStatus: Codable, Sendable, Hashable {
    public var appName: String?
    public var instanceName: String?
    public var version: String
    public var buildTime: Date?
    public var startTime: Date?
    public var osName: String?
    public var osVersion: String?
    public var branch: String?
    public var authentication: String?
    public var urlBase: String?
    public var runtimeVersion: String?
    public var databaseType: String?
    public var isDocker: Bool?
    public var appData: String?
    public var startupPath: String?
}

public struct ArrHealth: Codable, Sendable, Hashable, Identifiable {
    public var source: String?
    public var type: String
    public var message: String
    public var wikiUrl: String?
    public var id: String { (source ?? "") + message }
    public var isError: Bool { type.lowercased() == "error" }
}

public struct ArrDiskSpace: Codable, Sendable, Hashable, Identifiable {
    public var path: String
    public var label: String?
    public var freeSpace: Int64
    public var totalSpace: Int64
    public var id: String { path }
    public var usedFraction: Double { totalSpace > 0 ? Double(totalSpace - freeSpace) / Double(totalSpace) : 0 }
}

public struct ArrQualityProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}

public struct ArrRootFolder: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var path: String
    public var freeSpace: Int64?
    public var accessible: Bool?
}

public struct ArrTag: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var label: String
}

public struct ArrImage: Codable, Sendable, Hashable {
    public var coverType: String
    public var url: String?
    public var remoteUrl: String?
}

public extension Array where Element == ArrImage {
    func image(_ type: String) -> ArrImage? { first { $0.coverType == type } }
}

public struct ArrLanguage: Codable, Sendable, Hashable {
    public var id: Int?
    public var name: String?
}

public struct ArrQualityInfo: Codable, Sendable, Hashable {
    public var id: Int?
    public var name: String?
    public var source: String?
    public var resolution: Int?
}

public struct ArrQuality: Codable, Sendable, Hashable {
    public var quality: ArrQualityInfo?
    public var revision: Revision?
    public struct Revision: Codable, Sendable, Hashable {
        public var version: Int?
        public var real: Int?
        public var isRepack: Bool?
    }
    public var name: String { quality?.name ?? "Unknown" }
}

public struct ArrMediaInfo: Codable, Sendable, Hashable {
    public var audioBitrate: Int64?
    public var audioChannels: Double?
    public var audioCodec: String?
    public var audioLanguages: String?
    public var audioStreamCount: Int?
    public var videoBitDepth: Int?
    public var videoBitrate: Int64?
    public var videoCodec: String?
    public var videoFps: Double?
    public var videoDynamicRange: String?
    public var videoDynamicRangeType: String?
    public var resolution: String?
    public var runTime: String?
    public var scanType: String?
    public var subtitles: String?
}

public struct ArrCustomFormat: Codable, Sendable, Hashable {
    public var id: Int?
    public var name: String?
}

public struct ArrStatusMessage: Codable, Sendable, Hashable {
    public var title: String?
    public var messages: [String]?
}

public struct ArrCommand: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var commandName: String?
    public var status: String?
    public var queued: Date?
    public var started: Date?
    public var ended: Date?
    public var message: String?
    public var trigger: String?
}

public struct ArrTask: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var taskName: String
    public var interval: Int
    public var lastExecution: Date?
    public var lastStartTime: Date?
    public var nextExecution: Date?
    public var lastDuration: String?
}

public struct ArrLogRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var time: Date
    public var level: String
    public var logger: String?
    public var message: String?
    public var exception: String?
    public var exceptionType: String?
}

public struct ArrPage<T: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public var page: Int
    public var pageSize: Int
    public var totalRecords: Int
    public var records: [T]
    public var sortKey: String?
    public var sortDirection: String?
}

/// A release returned by an *arr interactive search.
public struct ArrRelease: Codable, Sendable, Hashable, Identifiable {
    public var guid: String
    public var title: String
    public var indexer: String?
    public var indexerId: Int?
    public var size: Int64?
    public var age: Int?
    public var ageHours: Double?
    public var ageMinutes: Double?
    public var publishDate: Date?
    public var seeders: Int?
    public var leechers: Int?
    public var `protocol`: String?
    public var approved: Bool?
    public var rejected: Bool?
    public var temporarilyRejected: Bool?
    public var rejections: [String]?
    public var quality: ArrQuality?
    public var customFormatScore: Int?
    public var customFormats: [ArrCustomFormat]?
    public var downloadUrl: String?
    public var infoUrl: String?
    public var languages: [ArrLanguage]?
    public var releaseGroup: String?
    public var downloadAllowed: Bool?
    public var releaseWeight: Int?
    public var fullSeason: Bool?
    public var seasonNumber: Int?
    public var episodeNumbers: [Int]?
    public var mappedEpisodeNumbers: [Int]?
    public var movieId: Int?
    public var mappedMovieId: Int?
    public var seriesId: Int?
    public var mappedSeriesId: Int?
    public var id: String { guid + "|" + String(indexerId ?? 0) }
    public var isTorrent: Bool { `protocol`?.lowercased() == "torrent" }
}

public struct ArrHistoryRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var date: Date
    public var eventType: String
    public var sourceTitle: String?
    public var quality: ArrQuality?
    public var downloadId: String?
    public var data: [String: String?]?
    public var movieId: Int?
    public var seriesId: Int?
    public var episodeId: Int?
    public var movie: RadarrMovie?
    public var series: SonarrSeries?
    public var episode: SonarrEpisode?

    public var eventLabel: String {
        switch eventType {
        case "grabbed": "Grabbed"
        case "downloadFolderImported", "seriesFolderImported", "movieFolderImported": "Imported"
        case "downloadFailed": "Download Failed"
        case "movieFileDeleted", "episodeFileDeleted": "File Deleted"
        case "movieFileRenamed", "episodeFileRenamed": "Renamed"
        case "downloadIgnored": "Ignored"
        default: eventType.prefix(1).uppercased() + eventType.dropFirst()
        }
    }
    public var dataValue: (String) -> String? { { key in self.data?[key] ?? nil } }
}

/// Queue item (shared shape between Radarr and Sonarr).
public struct ArrQueueItem: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String?
    public var status: String?
    public var trackedDownloadStatus: String?
    public var trackedDownloadState: String?
    public var statusMessages: [ArrStatusMessage]?
    public var errorMessage: String?
    public var size: Double?
    public var sizeleft: Double?
    public var timeleft: String?
    public var estimatedCompletionTime: Date?
    public var added: Date?
    public var downloadClient: String?
    public var downloadId: String?
    public var `protocol`: String?
    public var indexer: String?
    public var outputPath: String?
    public var quality: ArrQuality?
    public var customFormatScore: Int?
    public var movieId: Int?
    public var seriesId: Int?
    public var episodeId: Int?
    public var seasonNumber: Int?
    public var movie: RadarrMovie?
    public var series: SonarrSeries?
    public var episode: SonarrEpisode?

    public var progress: Double {
        guard let size, size > 0, let sizeleft else { return 0 }
        return max(0, min(1, (size - sizeleft) / size))
    }
    public var hasWarning: Bool {
        trackedDownloadStatus?.lowercased() == "warning" || trackedDownloadStatus?.lowercased() == "error"
    }
}

public struct ArrQueueStatus: Codable, Sendable, Hashable {
    public var totalCount: Int?
    public var count: Int?
    public var unknownCount: Int?
    public var errors: Bool?
    public var warnings: Bool?
}

/// Arr "add options" monitor modes for Sonarr.
public enum SonarrMonitorOption: String, CaseIterable, Sendable, Identifiable {
    case all, future, missing, existing, recent, pilot, firstSeason, lastSeason, monitorSpecials, unmonitorSpecials, none
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .all: "All Episodes"
        case .future: "Future Episodes"
        case .missing: "Missing Episodes"
        case .existing: "Existing Episodes"
        case .recent: "Recent Episodes"
        case .pilot: "Pilot Episode"
        case .firstSeason: "First Season"
        case .lastSeason: "Last Season"
        case .monitorSpecials: "Monitor Specials"
        case .unmonitorSpecials: "Unmonitor Specials"
        case .none: "None"
        }
    }
}

public enum RadarrAvailability: String, CaseIterable, Sendable, Identifiable {
    case announced, inCinemas, released
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .announced: "Announced"
        case .inCinemas: "In Cinemas"
        case .released: "Released"
        }
    }
}
