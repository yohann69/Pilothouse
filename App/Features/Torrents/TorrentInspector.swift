import SwiftUI
import PilothouseKit
import UniformTypeIdentifiers

/// Folder/file tree built from qBittorrent's flat file list.
struct FileNode: Identifiable, Hashable {
    let id: String          // full path
    let name: String
    var children: [FileNode]?
    var indices: [Int]      // file indexes covered by this node
    var size: Int64
    var downloaded: Double  // bytes
    var priority: Int?      // nil = mixed
    var progress: Double { size > 0 ? downloaded / Double(size) : 0 }
    var isFolder: Bool { children != nil }

    static func build(_ files: [QBFile]) -> [FileNode] {
        final class Box { var name: String; var path: String; var dirs: [String: Box] = [:]; var order: [String] = []; var files: [QBFile] = []
            init(_ n: String, _ p: String) { name = n; path = p } }
        let root = Box("", "")
        for f in files {
            let parts = f.name.split(separator: "/").map(String.init)
            var cur = root
            for d in parts.dropLast() {
                if cur.dirs[d] == nil { cur.dirs[d] = Box(d, cur.path.isEmpty ? d : cur.path + "/" + d); cur.order.append(d) }
                cur = cur.dirs[d]!
            }
            cur.files.append(f)
        }
        func convert(_ b: Box) -> [FileNode] {
            var out: [FileNode] = []
            for d in b.order.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                let kids = convert(b.dirs[d]!)
                let prios = Set(kids.map(\.priority))
                out.append(FileNode(id: b.dirs[d]!.path + "/", name: d, children: kids, indices: kids.flatMap(\.indices),
                                    size: kids.reduce(0) { $0 + $1.size }, downloaded: kids.reduce(0) { $0 + $1.downloaded },
                                    priority: prios.count == 1 ? (prios.first ?? nil) : nil))
            }
            for f in b.files.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                out.append(FileNode(id: f.name, name: (f.name as NSString).lastPathComponent, children: nil, indices: [f.index ?? 0],
                                    size: f.size, downloaded: Double(f.size) * f.progress, priority: f.priority))
            }
            return out
        }
        return convert(root)
    }
}

struct TorrentInspector: View {
    let store: TorrentStore
    let torrent: QBTorrent
    @AppStorage("torrentInspectorTab") private var tab = Tab.general
    @State private var props: QBProperties?
    @State private var files: [QBFile] = []
    @State private var trackers: [QBTracker] = []
    @State private var peers: [QBPeer] = []
    @State private var webSeeds: [String] = []
    @State private var newTrackers = ""
    @State private var newPeer = ""
    @State private var newSeed = ""
    @State private var renaming: FileNode?
    @State private var editingTracker: QBTracker?
    @State private var textInput = ""

    enum Tab: String, CaseIterable, Identifiable {
        case general, content, trackers, peers, sources
        var id: String { rawValue }
        var label: String {
            switch self { case .general: "General"; case .content: "Content"; case .trackers: "Trackers"; case .peers: "Peers"; case .sources: "HTTP" }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal).padding(.bottom, 8)
            Divider()
            Group {
                switch tab {
                case .general: TorrentControls(store: store, torrent: torrent, props: props)
                case .content: filesView
                case .trackers: trackersView
                case .peers: peersView
                case .sources: seedsView
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: "\(torrent.hash)-\(tab)") { await poll() }
        .sheet(item: $renaming) { node in
            TextPrompt(title: node.isFolder ? "Rename Folder" : "Rename File", text: node.id.hasSuffix("/") ? String(node.id.dropLast()) : node.id) { new in
                let h = torrent.hash
                let old = node.id.hasSuffix("/") ? String(node.id.dropLast()) : node.id
                store.perform("Renamed") { c in
                    if node.isFolder { try await c.renameFolder(h, oldPath: old, newPath: new) } else { try await c.renameFile(h, oldPath: old, newPath: new) }
                }
                refreshSoon()
            }
        }
        .sheet(item: $editingTracker) { t in
            TextPrompt(title: "Edit Tracker", text: t.url) { new in
                let h = torrent.hash
                store.perform("Tracker updated") { try await $0.editTracker(h, from: t.url, to: new) }
                refreshSoon()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(torrent.name).font(.headline).lineLimit(3).textSelection(.enabled)
            HStack {
                Label(torrent.stateLabel, systemImage: torrent.stateSymbol).foregroundStyle(torrent.stateColor)
                Spacer()
                Text("\(Fmt.percent(torrent.progress)) of \(torrent.size.byteString)").monospacedDigit()
            }
            .font(.callout)
            LinearProgress(value: torrent.progress, tint: torrent.stateColor, height: 6)
            HStack(spacing: 14) {
                Label(Fmt.speed(torrent.dlspeed), systemImage: "arrow.down").foregroundStyle(.blue)
                Label(Fmt.speed(torrent.upspeed), systemImage: "arrow.up").foregroundStyle(.green)
                if !torrent.isComplete { Label(Fmt.eta(torrent.eta), systemImage: "clock") }
                Label(Fmt.ratio(torrent.ratio), systemImage: "arrow.up.arrow.down")
            }
            .font(.caption.monospacedDigit())
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        store.perform { torrent.isPaused ? try await $0.resume([torrent.hash]) : try await $0.pause([torrent.hash]) }
                    } label: { Image(systemName: torrent.isPaused ? "play.fill" : "pause.fill") }
                        .help(torrent.isPaused ? "Resume" : "Pause")
                    Button { store.perform("Force started") { try await $0.setForceStart([torrent.hash], !torrent.forceStart) } } label: {
                        Image(systemName: torrent.forceStart ? "forward.fill" : "forward")
                    }
                    .help("Force start")
                    Button { store.perform("Rechecking") { try await $0.recheck([torrent.hash]) } } label: { Image(systemName: "checkmark.arrow.trianglehead.counterclockwise") }
                        .help("Force recheck")
                    Button { store.perform("Reannounced") { try await $0.reannounce([torrent.hash]) } } label: { Image(systemName: "megaphone") }
                        .help("Force reannounce")
                    Menu {
                        Button("Copy Magnet Link") { copyToPasteboard(torrent.magnetURI); AppModel.shared.flash("Magnet link copied") }
                        Button("Copy Info Hash") { copyToPasteboard(torrent.hash) }
                        Button("Copy Name") { copyToPasteboard(torrent.name) }
                        Divider()
                        Button("Export .torrent…") { exportTorrent() }
                    } label: { Image(systemName: "square.and.arrow.up") }
                        .menuStyle(.button).fixedSize()
                        .help("Share / export")
                }
                .buttonStyle(.glass)
            }
        }
        .padding()
    }

    private func poll() async {
        if tab == .peers { await store.client.clearPeers(torrent.hash) }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refresh() async {
        let c = store.client, h = torrent.hash
        switch tab {
        case .general: props = try? await c.properties(h)
        case .content: if let f = try? await c.files(h) { files = f }
        case .trackers: if let t = try? await c.trackers(h) { trackers = t }
        case .peers: if let p = try? await c.peers(h) { peers = p }
        case .sources: if let w = try? await c.webSeeds(h) { webSeeds = w }
        }
    }

    private func refreshSoon() { Task { try? await Task.sleep(for: .milliseconds(400)); await refresh() } }

    private func exportTorrent() {
        let h = torrent.hash, name = torrent.name
        Task {
            do {
                let data = try await store.client.exportTorrent(h)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name + ".torrent"
                panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url)
                    AppModel.shared.flash("Saved \(url.lastPathComponent)")
                }
            } catch {
                AppModel.shared.flash(error.localizedDescription, .error)
            }
        }
    }

    // MARK: Content

    private var filesView: some View {
        let built = FileNode.build(files)
        // A single top-level folder adds nothing: show its contents directly.
        let tree = built.count == 1 && built[0].isFolder ? (built[0].children ?? built) : built
        return VStack(spacing: 0) {
            List {
                OutlineGroup(tree, children: \.children) { node in fileRow(node) }
            }
            .listStyle(.inset)
            .overlay { if files.isEmpty { ProgressView() } }
            Divider()
            HStack {
                Text("\(files.count) files · \(files.filter { $0.priority > 0 }.reduce(Int64(0)) { $0 + $1.size }.byteString) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("All") { setPriority(files.compactMap(\.index), 1) }.controlSize(.small)
                Button("None") { setPriority(files.compactMap(\.index), 0) }.controlSize(.small)
            }
            .padding(8)
        }
    }

    private func fileRow(_ node: FileNode) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { (node.priority ?? 1) != 0 },
                set: { on in setPriority(node.indices, on ? 1 : 0) })
            )
            .toggleStyle(.checkbox).labelsHidden()
            .help(node.priority == nil ? "Some files skipped" : node.priority == 0 ? "Not downloaded" : "Downloaded")
            Image(systemName: node.isFolder ? "folder.fill" : fileIcon(node.name))
                .foregroundStyle(node.isFolder ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name).lineLimit(2).font(.callout).help(node.id)
                    .foregroundStyle(node.priority == 0 ? .secondary : .primary)
                HStack(spacing: 6) {
                    LinearProgress(value: node.progress, tint: node.progress >= 1 ? .green : .blue, height: 3).frame(maxWidth: 90)
                    Text("\(Fmt.percent(node.progress)) · \(node.size.byteString)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("Do Not Download") { setPriority(node.indices, 0) }
                Button("Normal") { setPriority(node.indices, 1) }
                Button("High") { setPriority(node.indices, 6) }
                Button("Maximum") { setPriority(node.indices, 7) }
                Divider()
                Button("Rename…") { renaming = node }
            } label: {
                Text(priorityLabel(node.priority)).font(.caption)
            }
            .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        }
        .contextMenu {
            Button("Do Not Download") { setPriority(node.indices, 0) }
            Button("Normal Priority") { setPriority(node.indices, 1) }
            Button("High Priority") { setPriority(node.indices, 6) }
            Button("Maximum Priority") { setPriority(node.indices, 7) }
            Divider()
            Button("Rename…") { renaming = node }
            Button("Copy Path") { copyToPasteboard(node.id) }
        }
    }

    private func priorityLabel(_ p: Int?) -> String {
        switch p { case nil: "Mixed"; case 0: "Skip"; case 6: "High"; case 7: "Max"; default: "Normal" }
    }

    private func fileIcon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mkv", "mp4", "avi", "mov", "m4v", "ts", "wmv": "film"
        case "srt", "ass", "sub", "idx", "vtt": "captions.bubble"
        case "mp3", "flac", "m4a", "aac", "wav", "ogg": "music.note"
        case "jpg", "jpeg", "png", "gif", "webp": "photo"
        case "nfo", "txt", "md": "doc.text"
        case "zip", "rar", "7z", "tar", "gz": "doc.zipper"
        case "iso", "img", "dmg": "opticaldisc"
        default: "doc"
        }
    }

    private func setPriority(_ ids: [Int], _ p: Int) {
        guard !ids.isEmpty else { return }
        let h = torrent.hash
        // Optimistic update so the checkbox reacts instantly.
        for i in files.indices where ids.contains(files[i].index ?? -1) { files[i].priority = p }
        store.perform { try await $0.setFilePriority(h, ids: ids, priority: p) }
        refreshSoon()
    }

    // MARK: Trackers

    private var trackersView: some View {
        VStack(spacing: 0) {
            List(trackers) { t in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        StatusDot(color: t.status == 2 ? .green : t.status == 4 ? .red : t.status == 0 ? .gray : .orange)
                        Text(t.url).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        if let tier = t.tier { Spacer(); Text("Tier \(tier)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    HStack(spacing: 10) {
                        Text(t.statusLabel)
                        if !t.isPseudo {
                            Text("Seeds \(max(0, t.num_seeds ?? 0))")
                            Text("Peers \(max(0, t.num_peers ?? 0))")
                            Text("Leeches \(max(0, t.num_leeches ?? 0))")
                            Text("Downloaded \(max(0, t.num_downloaded ?? 0))")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if let m = t.msg, !m.isEmpty { Text(m).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                }
                .contextMenu {
                    if !t.isPseudo {
                        Button("Edit URL…") { editingTracker = t }
                        Button("Copy URL") { copyToPasteboard(t.url) }
                        Divider()
                        Button("Remove Tracker", role: .destructive) {
                            let h = torrent.hash
                            store.perform("Tracker removed") { try await $0.removeTrackers(h, urls: [t.url]) }
                            refreshSoon()
                        }
                    }
                }
            }
            Divider()
            HStack {
                TextField("", text: $newTrackers, prompt: Text("Add tracker URL")).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let urls = newTrackers.split(whereSeparator: { $0.isNewline || $0 == " " }).map(String.init).filter { !$0.isEmpty }
                    let h = torrent.hash
                    store.perform("Tracker added") { try await $0.addTrackers(h, urls: urls) }
                    newTrackers = ""
                    refreshSoon()
                }
                .disabled(newTrackers.isEmpty)
            }
            .padding(8)
        }
    }

    // MARK: Peers

    private var peersView: some View {
        VStack(spacing: 0) {
            List(peers) { p in
                HStack(spacing: 8) {
                    Text(flag(p.countryCode)).help(p.country)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(p.ip):\(p.port)").font(.callout.monospaced()).textSelection(.enabled)
                        Text("\(p.client) · \(p.connection) · \(p.flags)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.percent(p.progress)).font(.caption.monospacedDigit())
                        HStack(spacing: 6) {
                            if p.dlSpeed > 0 { Text("↓\(Fmt.speed(p.dlSpeed))").foregroundStyle(.blue) }
                            if p.upSpeed > 0 { Text("↑\(Fmt.speed(p.upSpeed))").foregroundStyle(.green) }
                        }
                        .font(.caption2.monospacedDigit())
                    }
                }
                .contextMenu {
                    Button("Copy IP:Port") { copyToPasteboard("\(p.ip):\(p.port)") }
                    Button("Ban Peer Permanently", role: .destructive) {
                        store.perform("Peer banned") { try await $0.banPeers(["\(p.ip):\(p.port)"]) }
                    }
                }
            }
            .overlay { if peers.isEmpty { ContentUnavailableView("No Peers", systemImage: "person.2.slash") } }
            Divider()
            HStack {
                TextField("", text: $newPeer, prompt: Text("Add peer (ip:port)")).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let list = newPeer.split(whereSeparator: { $0 == "," || $0 == " " || $0.isNewline }).map(String.init)
                    let h = torrent.hash
                    store.perform("Peer added") { try await $0.addPeers([h], peers: list) }
                    newPeer = ""
                }
                .disabled(newPeer.isEmpty)
            }
            .padding(8)
        }
    }

    private func flag(_ code: String) -> String {
        guard code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }

    // MARK: Web seeds

    private var seedsView: some View {
        VStack(spacing: 0) {
            List(webSeeds, id: \.self) { url in
                Text(url).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .contextMenu {
                        Button("Copy URL") { copyToPasteboard(url) }
                        Button("Remove", role: .destructive) {
                            let h = torrent.hash
                            store.perform("Web seed removed") { try await $0.removeWebSeeds(h, urls: [url]) }
                            refreshSoon()
                        }
                    }
            }
            .overlay { if webSeeds.isEmpty { ContentUnavailableView("No HTTP Sources", systemImage: "link") } }
            Divider()
            HStack {
                TextField("", text: $newSeed, prompt: Text("Add web seed URL")).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let h = torrent.hash, u = newSeed
                    store.perform("Web seed added") { try await $0.addWebSeeds(h, urls: [u]) }
                    newSeed = ""
                    refreshSoon()
                }
                .disabled(newSeed.isEmpty)
            }
            .padding(8)
        }
    }
}

/// General tab: transfer info plus every per-torrent setting, editable in place.
struct TorrentControls: View {
    let store: TorrentStore
    let torrent: QBTorrent
    let props: QBProperties?
    @State private var dlKiB: Double = 0
    @State private var ulKiB: Double = 0
    @State private var savePath = ""
    @State private var ratioMode = 0
    @State private var ratio = 2.0
    @State private var timeMode = 0
    @State private var minutes = 1440.0
    @State private var loadedHash = ""

    private var h: [String] { [torrent.hash] }

    var body: some View {
        Form {
            SwiftUI.Section("Speed Limits") {
                LimitRow(title: "Download", kib: $dlKiB) { v in
                    store.perform(v == 0 ? "Download limit removed" : "Download limited to \(Fmt.speed(v * 1024))") { try await $0.setDownloadLimit([torrent.hash], v * 1024) }
                }
                LimitRow(title: "Upload", kib: $ulKiB) { v in
                    store.perform(v == 0 ? "Upload limit removed" : "Upload limited to \(Fmt.speed(v * 1024))") { try await $0.setUploadLimit([torrent.hash], v * 1024) }
                }
            }
            SwiftUI.Section("Share Limits") {
                Picker("Ratio", selection: $ratioMode) { Text("Global").tag(0); Text("Unlimited").tag(1); Text("Custom").tag(2) }
                if ratioMode == 2 { TextField("Max ratio", value: $ratio, format: .number) }
                Picker("Seeding time", selection: $timeMode) { Text("Global").tag(0); Text("Unlimited").tag(1); Text("Custom").tag(2) }
                if timeMode == 2 { TextField("Minutes", value: $minutes, format: .number) }
                Button("Apply Share Limits") {
                    let r = ratioMode == 0 ? -2 : ratioMode == 1 ? -1 : ratio
                    let m = timeMode == 0 ? -2 : timeMode == 1 ? -1 : Int(minutes)
                    store.perform("Share limits set") { try await $0.setShareLimits([torrent.hash], ratio: r, seedingMinutes: m) }
                }
            }
            SwiftUI.Section("Organize") {
                Picker("Category", selection: Binding(get: { torrent.category }, set: { v in
                    store.perform(v.isEmpty ? "Category removed" : "Category set to \(v)") { try await $0.setCategory([torrent.hash], v) }
                })) {
                    Text("None").tag("")
                    ForEach(store.categories) { Text($0.name).tag($0.name) }
                }
                if !store.tags.isEmpty {
                    LabeledContent("Tags") {
                        FlowLayout(spacing: 4) {
                            ForEach(store.tags, id: \.self) { tag in
                                let on = torrent.tags.contains(tag)
                                Button {
                                    store.perform { on ? try await $0.removeTags([torrent.hash], [tag]) : try await $0.addTags([torrent.hash], [tag]) }
                                } label: { Label(tag, systemImage: on ? "checkmark.circle.fill" : "circle") }
                                    .buttonStyle(.glass).controlSize(.mini)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Save path", text: $savePath)
                    Button("Move") {
                        let p = savePath
                        store.perform("Moving to \(p)") { try await $0.setLocation([torrent.hash], p) }
                    }
                    .disabled(savePath.isEmpty || savePath == torrent.savePath)
                }
            }
            SwiftUI.Section("Options") {
                Toggle("Sequential download", isOn: Binding(get: { torrent.seqDl }, set: { _ in store.perform { try await $0.toggleSequential([torrent.hash]) } }))
                Toggle("First and last pieces first", isOn: Binding(get: { torrent.firstLastPiecePrio }, set: { _ in store.perform { try await $0.toggleFirstLast([torrent.hash]) } }))
                Toggle("Automatic torrent management", isOn: Binding(get: { torrent.autoTMM }, set: { v in store.perform { try await $0.setAutoManagement([torrent.hash], v) } }))
                Toggle("Force start", isOn: Binding(get: { torrent.forceStart }, set: { v in store.perform { try await $0.setForceStart([torrent.hash], v) } }))
                Toggle("Super seeding", isOn: Binding(get: { torrent.superSeeding }, set: { v in store.perform { try await $0.setSuperSeeding([torrent.hash], v) } }))
                if store.server.queueing {
                    HStack {
                        Text("Queue position \(torrent.priority > 0 ? String(torrent.priority) : "—")")
                        Spacer()
                        Button { store.perform { try await $0.move([torrent.hash], .top) } } label: { Image(systemName: "arrow.up.to.line") }.help("Move to top")
                        Button { store.perform { try await $0.move([torrent.hash], .up) } } label: { Image(systemName: "arrow.up") }.help("Move up")
                        Button { store.perform { try await $0.move([torrent.hash], .down) } } label: { Image(systemName: "arrow.down") }.help("Move down")
                        Button { store.perform { try await $0.move([torrent.hash], .bottom) } } label: { Image(systemName: "arrow.down.to.line") }.help("Move to bottom")
                    }
                    .buttonStyle(.borderless)
                }
            }
            SwiftUI.Section("Transfer") {
                KeyValueRow(key: "Downloaded", value: Fmt.bytes(props?.total_downloaded ?? torrent.downloaded))
                KeyValueRow(key: "Uploaded", value: Fmt.bytes(props?.total_uploaded ?? torrent.uploaded))
                KeyValueRow(key: "Remaining", value: Fmt.bytes(torrent.amountLeft))
                KeyValueRow(key: "Average speed", value: "↓ \(Fmt.speed(props?.dl_speed_avg ?? 0))  ↑ \(Fmt.speed(props?.up_speed_avg ?? 0))")
                KeyValueRow(key: "Seeds", value: "\(props?.seeds ?? torrent.numSeeds) of \(props?.seeds_total ?? torrent.numComplete)")
                KeyValueRow(key: "Peers", value: "\(props?.peers ?? torrent.numLeechs) of \(props?.peers_total ?? torrent.numIncomplete)")
                KeyValueRow(key: "Connections", value: "\(props?.nb_connections ?? 0) / \(props?.nb_connections_limit ?? 0)")
                KeyValueRow(key: "Wasted", value: Fmt.bytes(props?.total_wasted))
                KeyValueRow(key: "Availability", value: torrent.availability < 0 ? "—" : String(format: "%.3f", torrent.availability))
                KeyValueRow(key: "Time active", value: Fmt.duration(props?.time_elapsed ?? torrent.timeActive))
                KeyValueRow(key: "Seeding time", value: Fmt.duration(props?.seeding_time ?? torrent.seedingTime))
                if let r = props?.reannounce { KeyValueRow(key: "Next announce", value: Fmt.eta(r)) }
            }
            SwiftUI.Section("Information") {
                KeyValueRow(key: "Save path", value: props?.save_path ?? torrent.savePath)
                KeyValueRow(key: "Added", value: Fmt.dateTime(torrent.addedOn))
                KeyValueRow(key: "Completed", value: Fmt.dateTime(torrent.completionOn))
                if let p = props {
                    KeyValueRow(key: "Pieces", value: "\(p.pieces_num ?? 0) × \(Fmt.bytes(p.piece_size)) (have \(p.pieces_have ?? 0))")
                    KeyValueRow(key: "Private", value: p.isPrivate == true ? "Yes" : "No")
                    if let c = p.comment, !c.isEmpty { KeyValueRow(key: "Comment", value: c) }
                    if let c = p.created_by, !c.isEmpty { KeyValueRow(key: "Created by", value: c) }
                    if let d = p.creation_date, d > 0 { KeyValueRow(key: "Created", value: Fmt.dateTime(Date(timeIntervalSince1970: d))) }
                }
                KeyValueRow(key: "Info hash", value: torrent.hash)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: torrent.hash) { load() }
    }

    private func load() {
        guard loadedHash != torrent.hash else { return }
        loadedHash = torrent.hash
        dlKiB = Double(max(0, torrent.dlLimit) / 1024)
        ulKiB = Double(max(0, torrent.upLimit) / 1024)
        savePath = torrent.savePath
        ratioMode = torrent.ratioLimit == -2 ? 0 : torrent.ratioLimit == -1 ? 1 : 2
        if ratioMode == 2 { ratio = torrent.ratioLimit }
    }
}

/// Speed limit editor: field + presets + apply. 0 = unlimited.
struct LimitRow: View {
    let title: String
    @Binding var kib: Double
    var apply: (Int) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $kib, format: .number, prompt: Text("∞"))
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .onSubmit { apply(Int(kib)) }
            Text("KiB/s").foregroundStyle(.secondary)
            Menu {
                ForEach([0, 128, 512, 1024, 2048, 5120, 10240, 25600, 51200], id: \.self) { v in
                    Button(v == 0 ? "Unlimited" : Int64(v * 1024).byteString + "/s") { kib = Double(v); apply(v) }
                }
            } label: { Image(systemName: "speedometer") }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
            Button("Set") { apply(Int(kib)) }.controlSize(.small)
        }
    }
}

/// Small sheet with one text field.
struct TextPrompt: View {
    let title: String
    @State var text: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("", text: $text).textFieldStyle(.roundedBorder).frame(width: 460)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(text); dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
