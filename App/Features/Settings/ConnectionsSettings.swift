import SwiftUI
import PilothouseKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Connections", systemImage: "server.rack") { ConnectionsSettings() }
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Appearance", systemImage: "paintbrush") { AppearanceSettings() }
            Tab("Sidebar", systemImage: "sidebar.left") { SidebarSettings() }
        }
        .frame(width: 820, height: 600)
    }
}

/// Result of the last connection test, per connection.
@Observable
final class ConnectionStatusCache {
    static let shared = ConnectionStatusCache()
    enum Status: Equatable { case testing, ok(String), failed(String) }
    var statuses: [UUID: Status] = [:]

    func test(_ config: ServiceConfig) {
        guard !config.url.isEmpty else { return }
        statuses[config.id] = .testing
        Task {
            do { statuses[config.id] = .ok(try await ConnectionTester.test(config)) }
            catch { statuses[config.id] = .failed(error.localizedDescription) }
        }
    }
}

// MARK: - Connections list

struct ConnectionsSettings: View {
    @Environment(AppModel.self) private var app
    @State private var editing: ServiceConfig?
    @State private var isNew = false
    @State private var showDiscovery = false
    @State private var deleting: ServiceConfig?
    private var status: ConnectionStatusCache { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connections").font(.title2.bold())
                    Text("Add as many servers as you like. Each section shows the active one.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { showDiscovery = true } label: { Label("Find on Network", systemImage: "dot.radiowaves.left.and.right") }
                            .help("Scan your local network for Radarr, Sonarr, Prowlarr, Seerr and qBittorrent")
                            .buttonStyle(.glass)
                        ImportBackupButton().buttonStyle(.glass)
                        Menu {
                            ForEach(ServiceKind.allCases) { k in
                                Button { add(k) } label: { Label(k.displayName, systemImage: k.symbol) }
                            }
                        } label: { Label("Add", systemImage: "plus") }
                            .menuStyle(.button).buttonStyle(.glassProminent).fixedSize()
                    }
                }
            }
            .padding(20)
            Divider()
            List {
                ForEach(ServiceKind.allCases) { kind in
                    SwiftUI.Section {
                        let list = app.connections(kind)
                        if list.isEmpty {
                            HStack {
                                Text("No \(kind.displayName) server").foregroundStyle(.secondary)
                                Spacer()
                                Button("Add…") { add(kind) }.buttonStyle(.link)
                            }
                        }
                        ForEach(list) { c in row(c) }
                            .onMove { app.move(kind: kind, from: $0, to: $1) }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.symbol).foregroundStyle(kind.tint)
                            Text(kind.displayName)
                            Spacer()
                            Button { add(kind) } label: { Image(systemName: "plus.circle") }
                                .buttonStyle(.borderless)
                                .help("Add a \(kind.displayName) server")
                        }
                        .font(.headline)
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
        }
        .sheet(item: $editing) { c in
            ConnectionEditor(config: c, isNew: isNew) { saved in
                app.upsert(saved)
                status.test(saved)
            }
        }
        .sheet(isPresented: $showDiscovery) { DiscoverySheet(kinds: ServiceKind.allCases) }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let d = deleting { app.remove(id: d.id) } }
        }
        .task { for c in app.services where status.statuses[c.id] == nil { status.test(c) } }
    }

    private func add(_ kind: ServiceKind) {
        isNew = true
        editing = ServiceConfig(kind: kind, name: app.suggestedName(kind))
    }

    private func row(_ c: ServiceConfig) -> some View {
        let isActive = app.activeID(c.kind) == c.id && app.instances(c.kind).count > 1
        return HStack(spacing: 12) {
            statusDot(c)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name).font(.body.weight(.medium))
                    if isActive { Pill(text: "Active", color: .accentColor) }
                    if !c.enabled { Pill(text: "Disabled", color: .secondary) }
                }
                Text(c.url.isEmpty ? "No URL" : c.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if case .failed(let e) = status.statuses[c.id] {
                    Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if case .ok(let v) = status.statuses[c.id] {
                    Text(v).font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { c.enabled }, set: { v in var n = c; n.enabled = v; app.upsert(n) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button { status.test(c) } label: { Label("Test", systemImage: "arrow.clockwise") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Test connection")
            Button("Edit") { isNew = false; editing = c }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onTapGesture(count: 2) { isNew = false; editing = c }
        .contextMenu {
            Button("Edit…") { isNew = false; editing = c }
            if app.instances(c.kind).count > 1, c.isConfigured {
                Button("Make Active") { app.setActive(c.kind, c.id) }
            }
            Button("Duplicate") {
                var d = c; d.id = UUID(); d.name = app.suggestedName(c.kind)
                isNew = true; editing = d
            }
            Button("Test Connection") { status.test(c) }
            Divider()
            Button("Delete…", role: .destructive) { deleting = c }
        }
    }

    @ViewBuilder
    private func statusDot(_ c: ServiceConfig) -> some View {
        switch status.statuses[c.id] {
        case .testing: ProgressView().controlSize(.mini).frame(width: 10)
        case .ok: StatusDot(color: .green)
        case .failed: StatusDot(color: .red)
        case nil: StatusDot(color: .secondary.opacity(0.4))
        }
    }
}

// MARK: - Editor

struct ConnectionEditor: View {
    @State var config: ServiceConfig
    let isNew: Bool
    var onSave: (ServiceConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var revealKey = false
    @State private var testing = false
    @State private var result: Result<String, Error>?
    @State private var showDetect = false
    @State private var fetchingKey = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: config.kind.symbol)
                    .font(.title2).foregroundStyle(config.kind.tint)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(config.kind.tint.opacity(0.15)), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New \(config.kind.displayName) Connection" : config.name).font(.title3.bold())
                    Text(config.kind.displayName).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $config.enabled).toggleStyle(.switch)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Name") { TextField("", text: $config.name, prompt: Text(config.kind.displayName)) }
                    field("Server URL", help: "Address and port, e.g. http://192.168.1.10:\(config.kind.defaultPort) — include a path if it's behind a reverse proxy.") {
                        HStack {
                            TextField("", text: $config.url, prompt: Text("http://192.168.1.10:\(config.kind.defaultPort)"))
                            Button { showDetect = true } label: { Label("Detect", systemImage: "dot.radiowaves.left.and.right") }
                                .buttonStyle(.glass)
                        }
                    }
                    field("Fallback URL", help: "Optional. Used automatically when the main URL can't be reached (for example a remote address).") {
                        TextField("", text: $config.fallbackURL, prompt: Text("Optional"))
                    }
                    if config.kind.usesAPIKey {
                        field("API Key", help: apiKeyHint) {
                            HStack {
                                Group {
                                    if revealKey { TextField("", text: $config.apiKey) } else { SecureField("", text: $config.apiKey) }
                                }
                                .font(.body.monospaced())
                                Button { revealKey.toggle() } label: { Image(systemName: revealKey ? "eye.slash" : "eye") }
                                    .buttonStyle(.borderless).help(revealKey ? "Hide" : "Show")
                                if [.radarr, .sonarr, .prowlarr].contains(config.kind) {
                                    Button { fetchKey() } label: {
                                        if fetchingKey { ProgressView().controlSize(.small) } else { Text("Fetch") }
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(config.url.isEmpty || fetchingKey)
                                    .help("Read the key from the server (works when authentication is disabled for local addresses)")
                                }
                            }
                        }
                    }
                    if config.kind.usesLogin {
                        HStack(alignment: .top, spacing: 14) {
                            field("Username") { TextField("", text: $config.username, prompt: Text("admin")) }
                            field("Password") { SecureField("", text: $config.password) }
                        }
                        Text("Leave both empty if qBittorrent skips authentication for your local network.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Advanced") {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Allow self-signed or invalid certificates", isOn: $config.allowInvalidCertificates)
                            HStack {
                                Text("Request timeout")
                                Slider(value: $config.timeout, in: 5...120, step: 5).frame(width: 220)
                                Text("\(Int(config.timeout)) s").monospacedDigit().foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Custom headers").font(.callout.weight(.medium))
                                ForEach($config.customHeaders) { $h in
                                    HStack {
                                        TextField("", text: $h.name, prompt: Text("Header")).frame(width: 200)
                                        TextField("", text: $h.value, prompt: Text("Value"))
                                        Button { config.customHeaders.removeAll { $0.id == h.id } } label: { Image(systemName: "minus.circle.fill") }
                                            .buttonStyle(.borderless).foregroundStyle(.red)
                                    }
                                }
                                Button { config.customHeaders.append(.init(name: "", value: "")) } label: { Label("Add Header", systemImage: "plus") }
                                    .buttonStyle(.link)
                            }
                        }
                        .padding(.top, 10)
                    }
                    if let result {
                        Group {
                            switch result {
                            case .success(let s): Label(s, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failure(let e): Label(e.localizedDescription, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                            }
                        }
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(20)
            }
            Divider()
            HStack {
                Button { test() } label: {
                    if testing { ProgressView().controlSize(.small) } else { Label("Test Connection", systemImage: "bolt.horizontal") }
                }
                .buttonStyle(.glass)
                .disabled(testing || config.url.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(config)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(config.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 600, height: 540)
        .sheet(isPresented: $showDetect) {
            DiscoverySheet(kinds: [config.kind]) { found in
                config.url = found.url
                if let key = found.apiKey, config.apiKey.isEmpty { config.apiKey = key }
                result = nil
            }
        }
    }

    private var apiKeyHint: String {
        config.kind == .seerr ? "Seerr › Settings › General › API Key" : "\(config.kind.displayName) › Settings › General › Security › API Key"
    }

    private func field<Content: View>(_ title: String, help: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            content()
            if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func fetchKey() {
        guard let url = ServiceConfig.normalize(config.url), let host = url.host() else { return }
        fetchingKey = true
        let port = url.port ?? config.kind.defaultPort
        Task {
            let found = await NetworkScanner.fingerprint(host: host, port: port, kinds: [config.kind])
            if let key = found.first?.apiKey {
                config.apiKey = key
                result = .success("API key fetched from \(config.kind.displayName)")
            } else {
                result = .failure(APIError.notConfigured("The server didn't share its API key — copy it from \(apiKeyHint)"))
            }
            fetchingKey = false
        }
    }
}

// MARK: - Discovery

struct DiscoverySheet: View {
    let kinds: [ServiceKind]
    /// When set, picking a result calls this instead of adding a connection.
    var onPick: ((DiscoveredService) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var found: [DiscoveredService] = []
    @State private var scanning = false
    @State private var manualHost = ""
    @State private var scanTask: Task<Void, Never>?

    private var title: String { kinds.count == 1 ? "Find \(kinds[0].displayName)" : "Find Services on Your Network" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text("Scans \(NetworkScanner.localSubnetPrefixes().map { "\($0).0/24" }.joined(separator: ", ").nilIfEmpty ?? "your network") on the usual ports.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if scanning { ProgressView().controlSize(.small) }
            }
            .padding(20)
            Divider()
            List {
                if found.isEmpty && !scanning {
                    ContentUnavailableView("Nothing Found", systemImage: "wifi.exclamationmark",
                                           description: Text("Make sure the services run and that Local Network access is allowed for this app in System Settings › Privacy & Security."))
                }
                ForEach(found) { s in
                    let exists = app.services.contains { $0.kind == s.kind && ServiceConfig.normalize($0.url) == ServiceConfig.normalize(s.url) }
                    HStack(spacing: 12) {
                        Image(systemName: s.kind.symbol).foregroundStyle(s.kind.tint).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(s.title).font(.body.weight(.medium))
                                if let v = s.version { Text(v).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(s.url).font(.caption.monospaced()).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if s.apiKey != nil { Pill(text: "API key found", color: .green, symbol: "key.fill") }
                                else if s.kind.usesAPIKey { Pill(text: "API key needed", color: .orange, symbol: "key") }
                                if s.needsLogin { Pill(text: "Login needed", color: .orange, symbol: "person.badge.key") }
                            }
                        }
                        Spacer()
                        if onPick != nil {
                            Button("Use") { onPick?(s); dismiss() }.buttonStyle(.glassProminent)
                        } else if exists {
                            Label("Added", systemImage: "checkmark").foregroundStyle(.secondary)
                        } else {
                            Button("Add") { add(s) }.buttonStyle(.glassProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Divider()
            HStack {
                TextField("", text: $manualHost, prompt: Text("Also scan host (IP or name)"))
                    .textFieldStyle(.roundedBorder).frame(width: 240)
                Button(scanning ? "Stop" : "Scan Again") { scanning ? stop() : start() }
                    .buttonStyle(.glass)
                Spacer()
                if onPick == nil {
                    let new = found.filter { s in !app.services.contains { $0.kind == s.kind && ServiceConfig.normalize($0.url) == ServiceConfig.normalize(s.url) } }
                    Button("Add All (\(new.count))") { new.forEach(add) }.disabled(new.isEmpty)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        stop()
        found = []
        scanning = true
        var extra = app.services.compactMap { ServiceConfig.normalize($0.url)?.host() }
        let manual = manualHost.trimmingCharacters(in: .whitespaces)
        if !manual.isEmpty { extra.insert(manual, at: 0) }
        let kinds = kinds
        scanTask = Task {
            for await s in NetworkScanner.scan(kinds: kinds, extraHosts: extra) {
                withAnimation(.snappy) {
                    found.append(s)
                    found.sort { ($0.kind.rawValue, $0.url) < ($1.kind.rawValue, $1.url) }
                }
            }
            scanning = false
        }
    }

    private func stop() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
    }

    private func add(_ s: DiscoveredService) {
        var c = ServiceConfig(kind: s.kind, name: app.suggestedName(s.kind))
        if s.title != s.kind.displayName, !s.title.isEmpty, app.connections(s.kind).isEmpty == false { c.name = s.title }
        c.url = s.url
        c.apiKey = s.apiKey ?? ""
        app.upsert(c)
        ConnectionStatusCache.shared.test(c)
        if s.kind.usesAPIKey && s.apiKey == nil {
            app.flash("\(c.name) added — enter its API key in Settings › Connections", .info)
        } else {
            app.flash("\(c.name) added")
        }
    }
}

// MARK: - Backup import

struct ImportBackupButton: View {
    @Environment(AppModel.self) private var app
    @State private var showImporter = false
    @State private var report: String?

    var body: some View {
        Button { showImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
            .help("Import servers from an nzb360 (Android) backup folder")
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
            let target = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            let backup = try NZB360Backup.load(from: target)
            let configs = backup.serviceConfigs()
            guard !configs.isEmpty else { app.flash("No servers found in that backup.", .error); return }
            for c in configs {
                var merged = c
                // Update an existing connection to the same server instead of duplicating it.
                if let existing = app.services.first(where: { $0.kind == c.kind && ServiceConfig.normalize($0.url) == ServiceConfig.normalize(c.url) }) {
                    merged.id = existing.id
                    merged.name = existing.name
                } else {
                    merged.name = app.suggestedName(c.kind)
                }
                app.upsert(merged)
            }
            Task {
                var lines: [String] = []
                for c in configs {
                    do { lines.append("✓ \(try await ConnectionTester.test(c))") }
                    catch { lines.append("✗ \(c.kind.displayName): \(error.localizedDescription)") }
                }
                report = "Imported \(configs.count) servers.\n\n" + lines.joined(separator: "\n") +
                    (lines.contains { $0.hasPrefix("✗") } ? "\n\nTip: use Find on Network to locate servers whose address changed." : "")
            }
        } catch {
            app.flash(error.localizedDescription, .error)
        }
    }
}
