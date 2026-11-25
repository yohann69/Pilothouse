import SwiftUI
import ArrcadeKit
import UserNotifications

/// Sidebar destinations.
enum Section: String, CaseIterable, Identifiable, Codable, Hashable {
    case dashboard, calendar, activity
    case movies, series
    case discover, requests, issues
    case torrents
    case search, indexers
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .calendar: "Calendar"
        case .activity: "Activity"
        case .movies: "Movies"
        case .series: "Series"
        case .discover: "Discover"
        case .requests: "Requests"
        case .issues: "Issues"
        case .torrents: "Torrents"
        case .search: "Search"
        case .indexers: "Indexers"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .calendar: "calendar"
        case .activity: "arrow.down.circle.dotted"
        case .movies: "film"
        case .series: "tv"
        case .discover: "sparkles"
        case .requests: "tray.and.arrow.down"
        case .issues: "exclamationmark.bubble"
        case .torrents: "arrow.up.arrow.down.circle"
        case .search: "magnifyingglass"
        case .indexers: "list.bullet.rectangle"
        case .system: "server.rack"
        }
    }

    var group: String {
        switch self {
        case .dashboard, .calendar, .activity: "Overview"
        case .movies, .series: "Library"
        case .discover, .requests, .issues: "Seerr"
        case .torrents: "Downloads"
        case .search, .indexers: "Prowlarr"
        case .system: "Server"
        }
    }

    /// Service(s) required for this section to be useful.
    var requires: [ServiceKind] {
        switch self {
        case .dashboard, .calendar, .activity, .system: []
        case .movies: [.radarr]
        case .series: [.sonarr]
        case .discover, .requests, .issues: [.seerr]
        case .torrents: [.qbittorrent]
        case .search, .indexers: [.prowlarr]
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .dashboard: "1"
        case .movies: "2"
        case .series: "3"
        case .discover: "4"
        case .requests: "5"
        case .torrents: "6"
        case .search: "7"
        case .calendar: "8"
        case .activity: "9"
        default: nil
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case success, error, info }
    let id = UUID()
    var message: String
    var style: Style
}

/// Root application state: service configuration, per-service stores, toasts and navigation.
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var services: [ServiceConfig] = []
    var selection: Section? = .dashboard
    var toasts: [Toast] = []
    var pendingMagnet: String?
    var pendingTorrentFiles: [URL] = []
    var showAddTorrent = false
    var globalSearchText = ""

    private(set) var radarr: RadarrStore?
    private(set) var sonarr: SonarrStore?
    private(set) var seerr: SeerrStore?
    private(set) var torrents: TorrentStore?
    private(set) var prowlarr: ProwlarrStore?

    private let fileURL: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Arrcade", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "services.json")
        // One-time migration from the app's pre-release name.
        let legacy = URL.applicationSupportDirectory.appending(path: "nbz360/services.json")
        if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: file)
        }
        return file
    }()

    private init() {
        load()
        rebuildStores()
    }

    // MARK: Config

    func config(_ kind: ServiceKind) -> ServiceConfig? {
        services.first { $0.kind == kind }
    }

    func isConfigured(_ kind: ServiceKind) -> Bool { config(kind)?.isConfigured ?? false }

    var hasAnyService: Bool { services.contains { $0.isConfigured } }

    func isAvailable(_ section: Section) -> Bool {
        section.requires.allSatisfy(isConfigured)
    }

    func upsert(_ config: ServiceConfig) {
        if let i = services.firstIndex(where: { $0.kind == config.kind }) {
            services[i] = config
        } else {
            services.append(config)
        }
        save()
        rebuildStores(only: config.kind)
    }

    func remove(_ kind: ServiceKind) {
        services.removeAll { $0.kind == kind }
        save()
        rebuildStores(only: kind)
    }

    func replaceAll(_ configs: [ServiceConfig]) {
        services = configs
        save()
        rebuildStores()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ServiceConfig].self, from: data) else { return }
        services = list
    }

    private func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(services).write(to: fileURL, options: [.atomic])
            // API keys / passwords live here: keep the file private to the user.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            flash("Couldn't save settings: \(error.localizedDescription)", .error)
        }
    }

    private func rebuildStores(only kind: ServiceKind? = nil) {
        func want(_ k: ServiceKind) -> ServiceConfig? {
            guard let c = config(k), c.isConfigured else { return nil }
            return c
        }
        if kind == nil || kind == .radarr { radarr = want(.radarr).map(RadarrStore.init) }
        if kind == nil || kind == .sonarr { sonarr = want(.sonarr).map(SonarrStore.init) }
        if kind == nil || kind == .seerr { seerr = want(.seerr).map(SeerrStore.init) }
        if kind == nil || kind == .prowlarr { prowlarr = want(.prowlarr).map(ProwlarrStore.init) }
        if kind == nil || kind == .qbittorrent {
            torrents?.stop()
            torrents = want(.qbittorrent).map(TorrentStore.init)
            torrents?.startBackground()
        }
    }

    // MARK: Toasts

    func flash(_ message: String, _ style: Toast.Style = .success) {
        let toast = Toast(message: message, style: style)
        withAnimation(.snappy) { toasts.append(toast) }
        Task {
            try? await Task.sleep(for: .seconds(style == .error ? 6 : 2.8))
            withAnimation(.smooth) { self.toasts.removeAll { $0.id == toast.id } }
        }
    }

    /// Run an async action, reporting success/failure as a toast.
    func run(_ success: String? = nil, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                if let success { flash(success) }
            } catch is CancellationError {
            } catch {
                flash(error.localizedDescription, .error)
            }
        }
    }

    // MARK: Incoming torrents

    func handle(url: URL) {
        if url.scheme?.lowercased() == "magnet" {
            pendingMagnet = url.absoluteString
            pendingTorrentFiles = []
            selection = .torrents
            showAddTorrent = true
        } else if url.isFileURL, url.pathExtension.lowercased() == "torrent" {
            pendingTorrentFiles.append(url)
            pendingMagnet = nil
            selection = .torrents
            showAddTorrent = true
        }
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
