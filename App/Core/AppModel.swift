import SwiftUI
import PilothouseKit
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
    var showQBOptions = false
    var globalSearchText = ""

    /// Every configured instance's store, keyed by config id.
    private(set) var radarrStores: [UUID: RadarrStore] = [:]
    private(set) var sonarrStores: [UUID: SonarrStore] = [:]
    private(set) var seerrStores: [UUID: SeerrStore] = [:]
    private(set) var torrentStores: [UUID: TorrentStore] = [:]
    private(set) var prowlarrStores: [UUID: ProwlarrStore] = [:]
    /// Which instance each section shows, per service kind.
    private(set) var activeIDs: [ServiceKind: UUID] = [:]

    // Active instance (what the per-service sections display).
    var radarr: RadarrStore? { activeStore(.radarr, radarrStores) }
    var sonarr: SonarrStore? { activeStore(.sonarr, sonarrStores) }
    var seerr: SeerrStore? { activeStore(.seerr, seerrStores) }
    var torrents: TorrentStore? { activeStore(.qbittorrent, torrentStores) }
    var prowlarr: ProwlarrStore? { activeStore(.prowlarr, prowlarrStores) }

    // All instances, in settings order (used by aggregate screens).
    var allRadarr: [RadarrStore] { ordered(.radarr, radarrStores) }
    var allSonarr: [SonarrStore] { ordered(.sonarr, sonarrStores) }
    var allTorrents: [TorrentStore] { ordered(.qbittorrent, torrentStores) }
    var allProwlarr: [ProwlarrStore] { ordered(.prowlarr, prowlarrStores) }
    var allSeerr: [SeerrStore] { ordered(.seerr, seerrStores) }

    private func ordered<S>(_ kind: ServiceKind, _ dict: [UUID: S]) -> [S] {
        instances(kind).compactMap { dict[$0.id] }
    }

    private func activeStore<S>(_ kind: ServiceKind, _ dict: [UUID: S]) -> S? {
        if let id = activeIDs[kind], let s = dict[id] { return s }
        return instances(kind).first.flatMap { dict[$0.id] }
    }

    private let fileURL: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Pilothouse", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "services.json")
        // One-time migration from earlier names of the app.
        for old in ["Arrcade", "nbz360"] {
            let legacy = URL.applicationSupportDirectory.appending(path: "\(old)/services.json")
            if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.copyItem(at: legacy, to: file)
            }
        }
        return file
    }()

    private init() {
        load()
        if let raw = UserDefaults.standard.dictionary(forKey: "activeInstances") as? [String: String] {
            for (k, v) in raw { if let kind = ServiceKind(rawValue: k), let id = UUID(uuidString: v) { activeIDs[kind] = id } }
        }
        rebuildStores()
    }

    // MARK: Config

    /// Enabled + complete instances of a service, in user order.
    func instances(_ kind: ServiceKind) -> [ServiceConfig] {
        services.filter { $0.kind == kind && $0.isConfigured }
    }

    /// All saved connections of a kind (including disabled/incomplete ones).
    func connections(_ kind: ServiceKind) -> [ServiceConfig] {
        services.filter { $0.kind == kind }
    }

    /// The active instance's config.
    func config(_ kind: ServiceKind) -> ServiceConfig? {
        let list = instances(kind)
        if let id = activeIDs[kind], let c = list.first(where: { $0.id == id }) { return c }
        return list.first ?? connections(kind).first
    }

    func activeID(_ kind: ServiceKind) -> UUID? { config(kind)?.id }

    func setActive(_ kind: ServiceKind, _ id: UUID) {
        activeIDs[kind] = id
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: activeIDs.map { ($0.key.rawValue, $0.value.uuidString) }), forKey: "activeInstances")
    }

    func isConfigured(_ kind: ServiceKind) -> Bool { !instances(kind).isEmpty }

    var hasAnyService: Bool { services.contains { $0.isConfigured } }

    func isAvailable(_ section: Section) -> Bool {
        section.requires.allSatisfy(isConfigured)
    }

    /// Insert or update a connection (matched by id).
    func upsert(_ config: ServiceConfig) {
        if let i = services.firstIndex(where: { $0.id == config.id }) {
            services[i] = config
        } else {
            services.append(config)
        }
        save()
        rebuildStores()
    }

    func remove(id: UUID) {
        services.removeAll { $0.id == id }
        save()
        rebuildStores()
    }

    func move(kind: ServiceKind, from: IndexSet, to: Int) {
        var list = connections(kind)
        list.move(fromOffsets: from, toOffset: to)
        services = services.filter { $0.kind != kind } + list
        save()
        rebuildStores()
    }

    /// Suggested name for a new connection ("Radarr", "Radarr 2", …).
    func suggestedName(_ kind: ServiceKind) -> String {
        let n = connections(kind).count
        return n == 0 ? kind.displayName : "\(kind.displayName) \(n + 1)"
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

    /// Re-create stores for new/changed connections, keep the others (and their caches).
    private func rebuildStores() {
        func sync<S>(_ kind: ServiceKind, _ dict: inout [UUID: S], config: (S) -> ServiceConfig, make: (ServiceConfig) -> S, drop: (S) -> Void = { _ in }) {
            let wanted = instances(kind)
            for (id, store) in dict where !wanted.contains(where: { $0.id == id && $0 == config(store) }) {
                drop(store)
                dict[id] = nil
            }
            for c in wanted where dict[c.id] == nil { dict[c.id] = make(c) }
        }
        sync(.radarr, &radarrStores, config: { $0.config }, make: RadarrStore.init)
        sync(.sonarr, &sonarrStores, config: { $0.config }, make: SonarrStore.init)
        sync(.seerr, &seerrStores, config: { $0.config }, make: SeerrStore.init)
        sync(.prowlarr, &prowlarrStores, config: { $0.config }, make: ProwlarrStore.init)
        sync(.qbittorrent, &torrentStores, config: { $0.config }, make: { c in
            let s = TorrentStore(config: c)
            s.startBackground()
            return s
        }, drop: { $0.stop() })
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
