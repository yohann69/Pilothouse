import SwiftUI
import PilothouseKit

struct ArrSystemSnapshot {
    var status: ArrSystemStatus?
    var health: [ArrHealth] = []
    var disks: [ArrDiskSpace] = []
    var tasks: [ArrTask] = []
    var error: String?
}

/// One *arr server shown on the System screen.
struct ArrEndpoint: Identifiable {
    let id: UUID
    let kind: ServiceKind
    let name: String
    let client: ArrClient
}

/// What a logs sheet reads from.
struct LogTarget: Identifiable {
    let id: UUID
    let kind: ServiceKind
    let name: String
    var arr: ArrClient?
    var qb: QBittorrentClient?
}

struct SystemView: View {
    @Environment(AppModel.self) private var app
    @State private var snapshots: [UUID: ArrSystemSnapshot] = [:]
    @State private var seerrStatus: [UUID: Result<SeerrStatus, Error>] = [:]
    @State private var logsFor: LogTarget?
    @State private var confirmRestart: ArrEndpoint?
    @State private var running = Set<String>()

    private var endpoints: [ArrEndpoint] {
        app.allRadarr.map { ArrEndpoint(id: $0.config.id, kind: .radarr, name: $0.name, client: $0.client) }
        + app.allSonarr.map { ArrEndpoint(id: $0.config.id, kind: .sonarr, name: $0.name, client: $0.client) }
        + app.allProwlarr.map { ArrEndpoint(id: $0.config.id, kind: .prowlarr, name: $0.name, client: $0.client) }
    }

    private var allConfigs: [ServiceConfig] { ServiceKind.allCases.flatMap { app.instances($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(allConfigs) { c in
                        ConnectionTile(config: c, version: version(c), error: error(c))
                    }
                }
                ForEach(endpoints) { serviceCard($0) }
                ForEach(app.allTorrents, id: \.config.id) { qbCard($0) }
            }
            .padding(20)
        }
        .navigationTitle("System")
        .toolbar { ToolbarItem { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } } }
        .task { await load() }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
        .sheet(item: $logsFor) { LogsSheet(target: $0) }
        .confirmationDialog("Restart \(confirmRestart?.name ?? "")?", isPresented: Binding(get: { confirmRestart != nil }, set: { if !$0 { confirmRestart = nil } })) {
            Button("Restart", role: .destructive) {
                if let e = confirmRestart { app.run("\(e.name) is restarting") { try await e.client.restart() } }
            }
        }
    }

    private func version(_ c: ServiceConfig) -> String? {
        switch c.kind {
        case .qbittorrent: app.torrentStores[c.id]?.version
        case .seerr: (try? seerrStatus[c.id]?.get())?.version
        default: snapshots[c.id]?.status?.version
        }
    }

    private func error(_ c: ServiceConfig) -> String? {
        switch c.kind {
        case .qbittorrent: return app.torrentStores[c.id]?.state.error
        case .seerr:
            if case .failure(let e)? = seerrStatus[c.id] { return e.localizedDescription }
            return nil
        default: return snapshots[c.id]?.error
        }
    }

    private func load() async {
        await withTaskGroup(of: (UUID, ArrSystemSnapshot).self) { g in
            for e in endpoints {
                let c = e.client
                let id = e.id
                g.addTask {
                    var s = ArrSystemSnapshot()
                    do {
                        s.status = try await c.systemStatus()
                        async let h = try? c.health()
                        async let d = try? c.diskSpace()
                        async let t = try? c.tasks()
                        let (hh, dd, tt) = await (h, d, t)
                        s.health = hh ?? []; s.disks = dd ?? []; s.tasks = tt ?? []
                    } catch { s.error = error.localizedDescription }
                    return (id, s)
                }
            }
            for await (id, s) in g { snapshots[id] = s }
        }
        for st in app.allSeerr {
            do { seerrStatus[st.config.id] = .success(try await st.client.status()) } catch { seerrStatus[st.config.id] = .failure(error) }
        }
    }

    private func serviceCard(_ ep: ArrEndpoint) -> some View {
        let snap = snapshots[ep.id]
        let kind = ep.kind
        return GlassCard(title: ep.name, symbol: kind.symbol, tint: kind.tint) {
            if let e = snap?.error {
                Label(e, systemImage: "wifi.exclamationmark").foregroundStyle(.red)
            } else if let s = snap?.status {
                HStack(spacing: 18) {
                    KeyValueMini("Version", s.version)
                    KeyValueMini("OS", "\(s.osName ?? "") \(s.osVersion ?? "")")
                    if let st = s.startTime { KeyValueMini("Up Since", Fmt.relative(st)) }
                    KeyValueMini("Branch", s.branch ?? "—")
                    if s.isDocker == true { KeyValueMini("Runtime", "Docker") }
                    Spacer()
                    Button("Logs") { logsFor = LogTarget(id: ep.id, kind: kind, name: ep.name, arr: ep.client) }.buttonStyle(.glass)
                    Button("Restart") { confirmRestart = ep }.buttonStyle(.glass)
                }
                if !(snap?.health ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snap!.health) { h in
                            HStack(alignment: .top) {
                                Image(systemName: h.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").foregroundStyle(h.isError ? .red : .orange)
                                Text(h.message).font(.callout).textSelection(.enabled)
                                Spacer()
                                if let w = h.wikiUrl { Button { openWeb(w) } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.borderless) }
                            }
                        }
                    }
                } else {
                    Label("No health issues", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.callout)
                }
                if !(snap?.disks ?? []).isEmpty {
                    ForEach(snap!.disks) { d in DiskRow(disk: d) }
                }
                if !(snap?.tasks ?? []).isEmpty {
                    DisclosureGroup("Scheduled Tasks (\(snap!.tasks.count))") {
                        ForEach(snap!.tasks) { t in
                            HStack {
                                Text(t.name).font(.callout)
                                Spacer()
                                Text("every \(Fmt.duration(t.interval * 60))").font(.caption).foregroundStyle(.secondary)
                                Text("last \(Fmt.relative(t.lastExecution))").font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .trailing)
                                let key = "\(ep.id)-\(t.taskName)"
                                if running.contains(key) { ProgressView().controlSize(.small).frame(width: 60) } else {
                                    Button("Run") {
                                        running.insert(key)
                                        Task {
                                            do { try await ep.client.command(t.taskName); app.flash("\(t.name) started") }
                                            catch { app.flash(error.localizedDescription, .error) }
                                            running.remove(key)
                                        }
                                    }
                                    .buttonStyle(.glass).controlSize(.small).frame(width: 60)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private func qbCard(_ t: TorrentStore) -> some View {
        GlassCard(title: t.name, symbol: ServiceKind.qbittorrent.symbol, tint: .blue) {
            HStack(spacing: 18) {
                KeyValueMini("Version", t.version ?? "—")
                KeyValueMini("Connection", t.server.connectionStatus.capitalized)
                KeyValueMini("DHT Nodes", "\(t.server.dhtNodes)")
                KeyValueMini("Free Space", t.server.freeSpaceOnDisk.byteString)
                KeyValueMini("All-time ↓", t.server.allTimeDL.byteString)
                KeyValueMini("All-time ↑", t.server.allTimeUL.byteString)
                KeyValueMini("Ratio", t.server.globalRatio)
                Spacer()
                Button("Logs") { logsFor = LogTarget(id: t.config.id, kind: .qbittorrent, name: t.name, qb: t.client) }.buttonStyle(.glass)
            }
        }
    }
}

struct KeyValueMini: View {
    let k: String, v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.callout.weight(.medium)).textSelection(.enabled)
        }
    }
}

struct DiskRow: View {
    let disk: ArrDiskSpace
    var body: some View {
        HStack {
            Image(systemName: "internaldrive").foregroundStyle(.secondary)
            Text(disk.label?.nilIfEmpty ?? disk.path).font(.callout).lineLimit(1).frame(width: 200, alignment: .leading)
            LinearProgress(value: disk.usedFraction, tint: disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.75 ? .orange : .green, height: 7)
            Text("\(disk.freeSpace.byteString) free of \(disk.totalSpace.byteString)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 200, alignment: .trailing)
        }
    }
}

struct ConnectionTile: View {
    let config: ServiceConfig
    var kind: ServiceKind { config.kind }
    let version: String?
    let error: String?
    @Environment(AppModel.self) private var app
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.title2).foregroundStyle(kind.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name).font(.headline).lineLimit(1)
                Text(error != nil ? "Unreachable" : version.map { $0.hasPrefix("v") ? $0 : "v\($0)" } ?? "Connecting…").font(.caption).foregroundStyle(error != nil ? .red : .secondary)
                Text(config.url).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            StatusDot(color: error != nil ? .red : version != nil ? .green : .orange)
        }
        .padding(12)
        .glassEffect(.regular.tint(kind.tint.opacity(0.06)), in: .rect(cornerRadius: 16))
    }
}

struct LogsSheet: View {
    let target: LogTarget
    var kind: ServiceKind { target.kind }
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var lines: [(id: String, time: Date, level: String, logger: String, message: String)] = []
    @State private var level = "all"
    @State private var filter = ""
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(target.name) Logs").font(.title2.bold())
                Spacer()
                if kind != .qbittorrent {
                    Picker("Level", selection: $level) {
                        Text("All").tag("all"); Text("Info").tag("info"); Text("Warn").tag("warn"); Text("Error").tag("error")
                    }
                    .pickerStyle(.segmented).frame(width: 260)
                }
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            List(lines.filter { filter.isEmpty || $0.message.localizedCaseInsensitiveContains(filter) }, id: \.id) { l in
                HStack(alignment: .top, spacing: 8) {
                    Text(l.time.formatted(date: .abbreviated, time: .standard)).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
                    Text(l.level.uppercased()).font(.caption.bold()).foregroundStyle(color(l.level)).frame(width: 50, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.message).font(.caption.monospaced()).textSelection(.enabled)
                        if !l.logger.isEmpty { Text(l.logger).font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }
            .overlay { if loading { ProgressView() } }
        }
        .frame(width: 960, height: 640)
        .task(id: level) { await load() }
    }

    private func color(_ l: String) -> Color {
        switch l.lowercased() { case "error", "fatal", "critical": .red; case "warn", "warning": .orange; case "debug", "trace": .secondary; default: .blue }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if kind == .qbittorrent {
            let raw = (try? await target.qb?.log()) ?? []
            lines = raw.reversed().map { j in
                let t = j["type"]?.intValue ?? 1
                let lvl = t == 8 ? "critical" : t == 4 ? "warning" : t == 2 ? "info" : "normal"
                return ("\(j["id"]?.intValue ?? 0)", Date(timeIntervalSince1970: j["timestamp"]?.doubleValue ?? 0), lvl, "", j["message"]?.stringValue ?? "")
            }
            return
        }
        let page = try? await target.arr?.logs(pageSize: 200, level: level)
        lines = (page?.records ?? []).map { ("\($0.id)", $0.time, $0.level, $0.logger ?? "", ($0.message ?? "") + ($0.exception.map { "\n" + $0 } ?? "")) }
    }
}
