import SwiftUI
import PilothouseKit
import UniformTypeIdentifiers

enum ConnectionTester {
    /// Returns a description (e.g. "Radarr 7.0.3") or throws.
    static func test(_ config: ServiceConfig) async throws -> String {
        switch config.kind {
        case .radarr:
            let s = try await RadarrClient(config: config).systemStatus()
            return "\(s.appName ?? "Radarr") \(s.version)"
        case .sonarr:
            let s = try await SonarrClient(config: config).systemStatus()
            return "\(s.appName ?? "Sonarr") \(s.version)"
        case .prowlarr:
            let s = try await ProwlarrClient(config: config).systemStatus()
            return "\(s.appName ?? "Prowlarr") \(s.version)"
        case .seerr:
            let c = SeerrClient(config: config)
            let s = try await c.status()
            let me = try await c.me()
            return "Seerr \(s.version) · \(me.name)"
        case .qbittorrent:
            let c = QBittorrentClient(config: config)
            if !config.username.isEmpty { try await c.login() }
            let v = try await c.version()
            _ = try await c.sync()
            return "qBittorrent \(v)"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.torrentInterval) private var torrentInterval = 1.5
    @AppStorage(Prefs.backgroundInterval) private var backgroundInterval = 10.0
    @AppStorage(Prefs.notifyTorrentComplete) private var notifyComplete = true
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.menuBarShowsSpeed) private var menuBarSpeed = true
    @AppStorage(Prefs.calendarDays) private var calendarDays = 30
    @AppStorage(Prefs.deleteFilesDefault) private var deleteFiles = false
    @AppStorage(Prefs.seerrDefault4K) private var default4K = false

    var body: some View {
        Form {
            SwiftUI.Section("Refresh") {
                LabeledContent("Torrent list (visible)") {
                    Picker("", selection: $torrentInterval) {
                        Text("0.5 s").tag(0.5); Text("1 s").tag(1.0); Text("1.5 s").tag(1.5); Text("2 s").tag(2.0); Text("3 s").tag(3.0); Text("5 s").tag(5.0)
                    }
                    .labelsHidden().frame(width: 120)
                }
                LabeledContent("Background") {
                    Picker("", selection: $backgroundInterval) {
                        Text("5 s").tag(5.0); Text("10 s").tag(10.0); Text("30 s").tag(30.0); Text("1 min").tag(60.0)
                    }
                    .labelsHidden().frame(width: 120)
                }
                Text("Faster polling uses qBittorrent's incremental sync, so it stays light on the server.").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Notifications") {
                Toggle("Notify when a torrent finishes downloading", isOn: $notifyComplete)
                    .onChange(of: notifyComplete) { if notifyComplete { app.requestNotificationPermission() } }
            }
            SwiftUI.Section("Menu Bar") {
                Toggle("Show menu bar extra", isOn: $showMenuBar)
                Toggle("Show transfer speeds in the menu bar", isOn: $menuBarSpeed).disabled(!showMenuBar)
            }
            SwiftUI.Section("Behavior") {
                Stepper("Calendar agenda: \(calendarDays) days", value: $calendarDays, in: 7...120, step: 7)
                Toggle("Delete files by default when removing torrents/media", isOn: $deleteFiles)
                Toggle("Request in 4K by default (Seerr)", isOn: $default4K)
            }
            SwiftUI.Section("Integration") {
                Button("Make Pilothouse the default app for magnet links") {
                    if let id = Bundle.main.bundleIdentifier {
                        LSSetDefaultHandlerForURLScheme("magnet" as CFString, id as CFString)
                        app.flash("Pilothouse now opens magnet links")
                    }
                }
                Text("Settings are stored in ~/Library/Application Support/Pilothouse/services.json (readable only by your user).").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettings: View {
    @AppStorage(Prefs.posterSize) private var posterSize = PosterSize.medium
    @AppStorage(Prefs.tintedGlass) private var tinted = true
    @AppStorage(Prefs.preferLocalImages) private var preferLocal = false
    @AppStorage(Prefs.movieLayout) private var movieLayout = LibraryLayout.grid
    @AppStorage(Prefs.seriesLayout) private var seriesLayout = LibraryLayout.grid

    var body: some View {
        Form {
            SwiftUI.Section("Library") {
                Picker("Poster Size", selection: $posterSize) { ForEach(PosterSize.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                Picker("Movies Layout", selection: $movieLayout) { ForEach(LibraryLayout.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Series Layout", selection: $seriesLayout) { ForEach(LibraryLayout.allCases) { Text($0.rawValue.capitalized).tag($0) } }
            }
            SwiftUI.Section("Liquid Glass") {
                Toggle("Tint glass cards with each service's color", isOn: $tinted)
            }
            SwiftUI.Section("Images") {
                Toggle("Load artwork from my servers first (instead of TMDB/TVDB CDNs)", isOn: $preferLocal)
                Button("Clear Image Cache") {
                    try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "pilothouse-images"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SidebarSettings: View {
    @AppStorage(Prefs.sidebarHidden) private var hidden = StoredList<Section>([])
    @AppStorage(Prefs.sidebarOrder) private var order = StoredList<Section>(Section.allCases)

    private var items: [Section] { order.items + Section.allCases.filter { !order.items.contains($0) } }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Choose which sections appear in the sidebar and drag to reorder them within their group.").foregroundStyle(.secondary)
            List {
                ForEach(items) { s in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Toggle(isOn: Binding(get: { !hidden.items.contains(s) }, set: { on in
                            if on { hidden.items.removeAll { $0 == s } } else { hidden.items.append(s) }
                        })) {
                            Label(s.title, systemImage: s.symbol)
                        }
                        Spacer()
                        Text(s.group).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onMove { from, to in
                    var list = items
                    list.move(fromOffsets: from, toOffset: to)
                    order = StoredList(list)
                }
            }
            HStack {
                Spacer()
                Button("Reset") { hidden = StoredList([]); order = StoredList(Section.allCases) }
            }
        }
        .padding()
    }
}
