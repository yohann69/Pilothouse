import SwiftUI
import ArrcadeKit
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

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Servers", systemImage: "server.rack") { ServersSettings() }
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Appearance", systemImage: "paintbrush") { AppearanceSettings() }
            Tab("Sidebar", systemImage: "sidebar.left") { SidebarSettings() }
        }
        .frame(width: 760, height: 560)
    }
}

struct ImportBackupButton: View {
    @Environment(AppModel.self) private var app
    @State private var showImporter = false
    @State private var report: String?

    var body: some View {
        Button { showImporter = true } label: { Label("Import nzb360 Backup…", systemImage: "square.and.arrow.down") }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder, .data, .xml], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importBackup(url)
            }
            .alert("Backup Imported", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
                Button("OK") { report = nil }
            } message: { Text(report ?? "") }
    }

    private func importBackup(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            var target = url
            // Picking a file inside the backup folder: use its folder so we also read the indexers file.
            if !url.hasDirectoryPath { target = url.deletingLastPathComponent() }
            let backup = try NZB360Backup.load(from: target)
            let configs = backup.serviceConfigs()
            guard !configs.isEmpty else { app.flash("No servers found in that backup.", .error); return }
            for c in configs {
                var merged = c
                if let existing = app.config(c.kind) { merged.id = existing.id }
                app.upsert(merged)
            }
            Task {
                var lines: [String] = []
                for c in configs {
                    do { lines.append("✓ \(try await ConnectionTester.test(c))") }
                    catch { lines.append("✗ \(c.kind.displayName): \(error.localizedDescription)") }
                }
                report = "Imported \(configs.count) servers.\n\n" + lines.joined(separator: "\n") +
                    (lines.contains { $0.hasPrefix("✗") } ? "\n\nFix unreachable servers in Settings › Servers." : "")
            }
        } catch {
            app.flash(error.localizedDescription, .error)
        }
    }
}

struct ServersSettings: View {
    @Environment(AppModel.self) private var app
    @State private var selected: ServiceKind = .radarr

    var body: some View {
        HStack(spacing: 0) {
            List(ServiceKind.allCases, selection: Binding(get: { selected }, set: { if let v = $0 { selected = v } })) { kind in
                HStack {
                    Image(systemName: kind.symbol).foregroundStyle(kind.tint).frame(width: 20)
                    Text(kind.displayName)
                    Spacer()
                    StatusDot(color: app.isConfigured(kind) ? .green : app.config(kind) != nil ? .orange : .secondary.opacity(0.4))
                }
                .tag(kind)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            .safeAreaInset(edge: .bottom) {
                ImportBackupButton().buttonStyle(.glass).padding(10)
            }
            Divider()
            ServerForm(kind: selected).id(selected)
        }
    }
}

struct ServerForm: View {
    let kind: ServiceKind
    @Environment(AppModel.self) private var app
    @State private var config: ServiceConfig
    @State private var testing = false
    @State private var result: Result<String, Error>?
    @State private var revealKey = false

    init(kind: ServiceKind) {
        self.kind = kind
        _config = State(initialValue: AppModel.shared.config(kind) ?? ServiceConfig(kind: kind))
    }

    private var dirty: Bool { config != (app.config(kind) ?? ServiceConfig(id: config.id, kind: kind)) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SwiftUI.Section {
                    Toggle("Enabled", isOn: $config.enabled)
                    TextField("Name", text: $config.name)
                    TextField("URL", text: $config.url, prompt: Text("http://192.168.1.10:\(kind.defaultPort)"))
                    TextField("Fallback URL", text: $config.fallbackURL, prompt: Text("Optional — e.g. remote https://… used when the primary is unreachable"))
                } header: { Text("Connection") }
                SwiftUI.Section("Authentication") {
                    if kind.usesAPIKey {
                        HStack {
                            if revealKey { TextField("API Key", text: $config.apiKey) } else { SecureField("API Key", text: $config.apiKey) }
                            Button { revealKey.toggle() } label: { Image(systemName: revealKey ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                        }
                        Text(apiKeyHint).font(.caption).foregroundStyle(.secondary)
                    }
                    if kind.usesLogin {
                        TextField("Username", text: $config.username, prompt: Text("Leave empty if auth is bypassed for your LAN"))
                        SecureField("Password", text: $config.password)
                    }
                }
                SwiftUI.Section("Advanced") {
                    Toggle("Allow self-signed / invalid certificates", isOn: $config.allowInvalidCertificates)
                    Stepper("Timeout: \(Int(config.timeout)) s", value: $config.timeout, in: 5...120, step: 5)
                    ForEach($config.customHeaders) { $h in
                        HStack {
                            TextField("Header", text: $h.name)
                            TextField("Value", text: $h.value)
                            Button { config.customHeaders.removeAll { $0.id == h.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    Button { config.customHeaders.append(.init(name: "", value: "")) } label: { Label("Add Custom Header", systemImage: "plus") }
                }
                if let result {
                    SwiftUI.Section {
                        switch result {
                        case .success(let s): Label(s, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure(let e): Label(e.localizedDescription, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if app.config(kind) != nil {
                    Button("Remove", role: .destructive) {
                        app.remove(kind)
                        config = ServiceConfig(kind: kind)
                        result = nil
                    }
                }
                Spacer()
                Button {
                    test()
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Label("Test", systemImage: "bolt.horizontal") }
                }
                .buttonStyle(.glass)
                .disabled(testing || config.url.isEmpty)
                Button("Save") {
                    app.upsert(config)
                    app.flash("\(kind.displayName) saved")
                    test()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!dirty)
            }
            .padding()
        }
    }

    private var apiKeyHint: String {
        switch kind {
        case .seerr: "Seerr › Settings › General › API Key"
        default: "\(kind.displayName) › Settings › General › Security › API Key"
        }
    }

    private func test() {
        testing = true
        result = nil
        let c = config
        Task {
            do { result = .success(try await ConnectionTester.test(c)) } catch { result = .failure(error) }
            testing = false
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
                Button("Make Arrcade the default app for magnet links") {
                    if let id = Bundle.main.bundleIdentifier {
                        LSSetDefaultHandlerForURLScheme("magnet" as CFString, id as CFString)
                        app.flash("Arrcade now opens magnet links")
                    }
                }
                Text("Settings are stored in ~/Library/Application Support/Arrcade/services.json (readable only by your user).").font(.caption).foregroundStyle(.secondary)
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
                    try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "arrcade-images"))
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
