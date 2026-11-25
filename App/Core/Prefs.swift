import SwiftUI
import PilothouseKit

/// User-customizable preferences (AppStorage keys).
enum Prefs {
    static let torrentInterval = "torrentRefreshInterval"
    static let backgroundInterval = "backgroundRefreshInterval"
    static let posterSize = "posterSize"
    static let movieLayout = "movieLayout"
    static let seriesLayout = "seriesLayout"
    static let movieSort = "movieSort"
    static let movieSortAsc = "movieSortAscending"
    static let movieFilter = "movieFilter"
    static let seriesSort = "seriesSort"
    static let seriesSortAsc = "seriesSortAscending"
    static let seriesFilter = "seriesFilter"
    static let torrentFilter = "torrentFilter"
    static let notifyTorrentComplete = "notifyTorrentComplete"
    static let notifyArrImports = "notifyArrImports"
    static let showMenuBar = "showMenuBarExtra"
    static let menuBarShowsSpeed = "menuBarShowsSpeed"
    static let sidebarHidden = "sidebarHiddenSections"
    static let sidebarOrder = "sidebarOrder"
    static let dashboardCards = "dashboardCards"
    static let dashboardHidden = "dashboardHiddenCards"
    static let calendarDays = "calendarDays"
    static let confirmDestructive = "confirmDestructive"
    static let preferLocalImages = "preferLocalImages"
    static let showUnmonitoredCalendar = "showUnmonitoredCalendar"
    static let seerrDefault4K = "seerrDefault4K"
    static let tintedGlass = "tintedGlass"
    static let compactRows = "compactTorrentRows"
    static let torrentColumns = "torrentColumns"
    static let deleteFilesDefault = "deleteFilesDefault"
    static let searchDefaultType = "searchDefaultType"
}

enum PosterSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var width: CGFloat {
        switch self { case .small: 120; case .medium: 160; case .large: 210 }
    }
    var label: String { rawValue.capitalized }
}

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var symbol: String { self == .grid ? "square.grid.3x3" : "list.bullet" }
}

enum DashboardCard: String, CaseIterable, Identifiable, Codable {
    case transfer, health, queue, upcoming, requests, recentlyAdded, disk, indexers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transfer: "Transfers"
        case .health: "Health"
        case .queue: "Download Queue"
        case .upcoming: "Upcoming"
        case .requests: "Pending Requests"
        case .recentlyAdded: "Recently Downloaded"
        case .disk: "Disk Space"
        case .indexers: "Indexers"
        }
    }
    var symbol: String {
        switch self {
        case .transfer: "arrow.up.arrow.down"
        case .health: "heart.text.square"
        case .queue: "list.bullet.below.rectangle"
        case .upcoming: "calendar.badge.clock"
        case .requests: "tray.and.arrow.down"
        case .recentlyAdded: "checkmark.seal"
        case .disk: "internaldrive"
        case .indexers: "antenna.radiowaves.left.and.right"
        }
    }
}

/// A Codable list stored in AppStorage as JSON.
struct StoredList<T: Codable & Hashable>: RawRepresentable {
    var items: [T]
    init(_ items: [T]) { self.items = items }
    init?(rawValue: String) {
        guard let d = rawValue.data(using: .utf8), let v = try? JSONDecoder().decode([T].self, from: d) else { return nil }
        items = v
    }
    var rawValue: String {
        (try? String(decoding: JSONEncoder().encode(items), as: UTF8.self)) ?? "[]"
    }
}

extension ServiceKind {
    var symbol: String {
        switch self {
        case .radarr: "film.stack"
        case .sonarr: "play.tv"
        case .seerr: "sparkles.tv"
        case .qbittorrent: "arrow.up.arrow.down.circle"
        case .prowlarr: "antenna.radiowaves.left.and.right"
        }
    }
    var tint: Color {
        switch self {
        case .radarr: .yellow
        case .sonarr: .cyan
        case .seerr: .indigo
        case .qbittorrent: .blue
        case .prowlarr: .orange
        }
    }
}
