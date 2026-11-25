import SwiftUI
import ArrcadeKit
import UniformTypeIdentifiers

nonisolated extension QBTorrent {
    var addedValue: Date { addedOn ?? .distantPast }
    var completedValue: Date { completionOn ?? .distantPast }
    var etaValue: Int { eta <= 0 || eta >= 8_640_000 ? Int.max : eta }
    var queueValue: Int { priority <= 0 ? Int.max : priority }
    var tagsLabel: String { tags.joined(separator: ", ") }
}

enum TorrentAction: Identifiable {
    case delete([String]), location([String]), rename(QBTorrent), limits([String]), share([String]), newCategory([String]), tags([String])
    var id: String {
        switch self {
        case .delete(let h): "d" + h.joined()
        case .location(let h): "l" + h.joined()
        case .rename(let t): "r" + t.hash
        case .limits(let h): "lim" + h.joined()
        case .share(let h): "s" + h.joined()
        case .newCategory(let h): "c" + h.joined()
        case .tags(let h): "t" + h.joined()
        }
    }
}

struct TorrentsView: View {
    @Bindable var store: TorrentStore
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.torrentFilter) private var status = QBStateGroup.all
    @AppStorage(Prefs.torrentColumns) private var columns = TableColumnCustomization<QBTorrent>()
    @State private var category: String? = nil
    @State private var tag: String? = nil
    @State private var tracker: String? = nil
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\QBTorrent.addedValue, order: .reverse)]
    @AppStorage("torrentInspectorVisible") private var showInspector = false
    @State private var action: TorrentAction?
    @State private var showCategories = false
    @State private var showLimits = false
    @State private var dropTargeted = false

    private static let noCategory = "\u{0}none"

    private var filtered: [QBTorrent] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return store.torrents.filter { t in
            status.matches(t)
            && (category == nil || (category == Self.noCategory ? t.category.isEmpty : t.category == category))
            && (tag == nil || t.tags.contains(tag!))
            && (tracker == nil || t.trackerHost == tracker)
            && (q.isEmpty || t.name.localizedCaseInsensitiveContains(q) || t.hash.hasPrefix(q.lowercased()))
        }
        .sorted(using: sortOrder)
    }

    private var selectedTorrents: [QBTorrent] { store.torrents.filter { selection.contains($0.hash) } }

    var body: some View {
        StateSwitch(state: store.state, isEmpty: store.torrents.isEmpty && store.state != .loaded, retry: { store.refreshNow() }) {
            VStack(spacing: 0) {
                filterBar
                table
            }
            .safeAreaInset(edge: .bottom) { statusBar }
        }
        .navigationTitle("Torrents")
        .navigationSubtitle("\(filtered.count) of \(store.torrents.count)" + (store.version.map { " · qBittorrent \($0)" } ?? ""))
        .searchable(text: $search, placement: .toolbar, prompt: "Filter torrents")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            Group {
                if selection.count == 1, let t = selectedTorrents.first {
                    TorrentInspector(store: store, torrent: t)
                } else if selection.count > 1 {
                    ContentUnavailableView("\(selection.count) Torrents Selected", systemImage: "square.stack.3d.up",
                                           description: Text(selectedTorrents.reduce(Int64(0)) { $0 + $1.size }.byteString + " total"))
                } else {
                    ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select a torrent to see its details."))
                }
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
        }
        .onAppear { store.acquire() }
        .onDisappear { store.release() }
        .focusedSceneValue(\.refreshAction) { store.refreshNow() }
        .sheet(item: $action) { a in TorrentActionSheet(store: store, action: a) }
        .sheet(isPresented: $showCategories) { CategoryManagerSheet(store: store) }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 24).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .overlay { Label("Drop .torrent files or magnet links", systemImage: "arrow.down.doc").font(.title2).padding().glassEffect() }
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([QBStateGroup.all, .downloading, .seeding, .completed, .paused, .active, .stalled, .checking, .errored]) { g in
                        let count = store.torrents.filter { g.matches($0) }.count
                        if g == .all || count > 0 || status == g {
                            Button {
                                withAnimation(.snappy) { status = g }
                            } label: {
                                Label("\(g.label) \(count)", systemImage: g.symbol).monospacedDigit()
                            }
                            .buttonStyle(status == g ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
                            .controlSize(.small)
                        }
                    }
                    Divider().frame(height: 18)
                    filterMenu("Category", value: $category, options: [(Self.noCategory, "Uncategorized")] + store.categories.map { ($0.name, $0.name) }, symbol: "folder")
                    filterMenu("Tag", value: $tag, options: store.tags.map { ($0, $0) }, symbol: "tag")
                    filterMenu("Tracker", value: $tracker, options: Set(store.torrents.map(\.trackerHost)).filter { !$0.isEmpty }.sorted().map { ($0, $0) }, symbol: "antenna.radiowaves.left.and.right")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    private func filterMenu(_ title: String, value: Binding<String?>, options: [(String, String)], symbol: String) -> some View {
        Menu {
            Button("All") { value.wrappedValue = nil }
            Divider()
            ForEach(options, id: \.0) { opt in
                Button {
                    value.wrappedValue = opt.0
                } label: {
                    let n = count(title, opt.0)
                    if value.wrappedValue == opt.0 { Label("\(opt.1) (\(n))", systemImage: "checkmark") } else { Text("\(opt.1) (\(n))") }
                }
            }
        } label: {
            Label(value.wrappedValue.map { $0 == Self.noCategory ? "Uncategorized" : $0 } ?? title, systemImage: symbol)
        }
        .menuStyle(.button)
        .buttonStyle(value.wrappedValue == nil ? AnyPrimitiveButtonStyle(.glass) : AnyPrimitiveButtonStyle(.glassProminent))
        .controlSize(.small)
        .fixedSize()
    }

    private func count(_ kind: String, _ v: String) -> Int {
        switch kind {
        case "Category": store.torrents.filter { v == Self.noCategory ? $0.category.isEmpty : $0.category == v }.count
        case "Tag": store.torrents.filter { $0.tags.contains(v) }.count
        default: store.torrents.filter { $0.trackerHost == v }.count
        }
    }

    // MARK: Table

    private var table: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            Group {
                TableColumn("Name", value: \QBTorrent.name) { t in
                    HStack(spacing: 8) {
                        Image(systemName: t.stateSymbol).foregroundStyle(t.stateColor)
                        Text(t.name).lineLimit(1).help(t.name)
                    }
                }
                .width(min: 200, ideal: 380)
                .customizationID("name")
                .disabledCustomizationBehavior(.visibility)
                TableColumn("Size", value: \QBTorrent.size) { t in Text(t.size.byteString).monospacedDigit() }
                    .width(min: 60, ideal: 80).customizationID("size")
                TableColumn("Progress", value: \QBTorrent.progress) { t in
                    HStack(spacing: 6) {
                        LinearProgress(value: t.progress, tint: t.stateColor, height: 6)
                        Text(Fmt.percent(t.progress)).font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                    }
                }
                .width(min: 100, ideal: 140).customizationID("progress")
                TableColumn("Status", value: \QBTorrent.stateLabel) { t in Text(t.stateLabel).foregroundStyle(t.stateColor) }
                    .width(min: 80, ideal: 110).customizationID("status")
                TableColumn("Down", value: \QBTorrent.dlspeed) { t in Text(t.dlspeed > 0 ? Fmt.speed(t.dlspeed) : "").monospacedDigit().foregroundStyle(.blue) }
                    .width(min: 60, ideal: 85).customizationID("down")
                TableColumn("Up", value: \QBTorrent.upspeed) { t in Text(t.upspeed > 0 ? Fmt.speed(t.upspeed) : "").monospacedDigit().foregroundStyle(.green) }
                    .width(min: 60, ideal: 85).customizationID("up")
                TableColumn("ETA", value: \QBTorrent.etaValue) { t in Text(t.isComplete ? "" : Fmt.eta(t.eta)).monospacedDigit() }
                    .width(min: 40, ideal: 65).customizationID("eta")
            }
            Group {
                TableColumn("Ratio", value: \QBTorrent.ratio) { t in Text(Fmt.ratio(t.ratio)).monospacedDigit() }
                    .width(min: 40, ideal: 50).customizationID("ratio")
                TableColumn("Seeds", value: \QBTorrent.numSeeds) { t in Text("\(t.numSeeds) (\(t.numComplete))").monospacedDigit() }
                    .width(min: 50, ideal: 70).customizationID("seeds")
                TableColumn("Peers", value: \QBTorrent.numLeechs) { t in Text("\(t.numLeechs) (\(t.numIncomplete))").monospacedDigit() }
                    .width(min: 50, ideal: 70).customizationID("peers")
                TableColumn("Category", value: \QBTorrent.category) { t in Text(t.category) }
                    .width(min: 60, ideal: 90).customizationID("category")
                TableColumn("Tags", value: \QBTorrent.tagsLabel) { t in Text(t.tagsLabel).foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 90).customizationID("tags").defaultVisibility(.hidden)
                TableColumn("Added", value: \QBTorrent.addedValue) { t in Text(Fmt.dateTime(t.addedOn)) }
                    .width(min: 90, ideal: 130).customizationID("added")
                TableColumn("Completed", value: \QBTorrent.completedValue) { t in Text(t.completionOn.map { Fmt.dateTime($0) } ?? "") }
                    .width(min: 90, ideal: 130).customizationID("completed").defaultVisibility(.hidden)
            }
            Group {
                TableColumn("Tracker", value: \QBTorrent.tracker) { t in Text(t.trackerHost) }
                    .width(min: 80, ideal: 130).customizationID("tracker").defaultVisibility(.hidden)
                TableColumn("Save Path", value: \QBTorrent.savePath) { t in Text(t.savePath).foregroundStyle(.secondary) }
                    .width(min: 100, ideal: 180).customizationID("path").defaultVisibility(.hidden)
                TableColumn("Downloaded", value: \QBTorrent.downloaded) { t in Text(t.downloaded.byteString).monospacedDigit() }
                    .width(min: 60, ideal: 85).customizationID("downloaded").defaultVisibility(.hidden)
                TableColumn("Uploaded", value: \QBTorrent.uploaded) { t in Text(t.uploaded.byteString).monospacedDigit() }
                    .width(min: 60, ideal: 85).customizationID("uploaded").defaultVisibility(.hidden)
                TableColumn("Queue", value: \QBTorrent.queueValue) { t in Text(t.priority > 0 ? "\(t.priority)" : "*").monospacedDigit() }
                    .width(min: 30, ideal: 45).customizationID("queue").defaultVisibility(.hidden)
                TableColumn("Availability", value: \QBTorrent.availability) { t in Text(t.availability < 0 ? "" : String(format: "%.2f", t.availability)).monospacedDigit() }
                    .width(min: 40, ideal: 60).customizationID("availability").defaultVisibility(.hidden)
                TableColumn("Seeding Time", value: \QBTorrent.seedingTime) { t in Text(t.seedingTime > 0 ? Fmt.duration(t.seedingTime) : "") }
                    .width(min: 60, ideal: 90).customizationID("seedtime").defaultVisibility(.hidden)
            }
        }
        .contextMenu(forSelectionType: String.self) { hashes in
            TorrentContextMenu(store: store, hashes: Array(hashes), action: $action)
        } primaryAction: { hashes in
            if let h = hashes.first, let t = store.torrents.first(where: { $0.hash == h }) {
                store.perform { t.isPaused ? try await $0.resume([h]) : try await $0.pause([h]) }
            }
        }
        .onDeleteCommand { if !selection.isEmpty { action = .delete(Array(selection)) } }
    }

    // MARK: Toolbar / status

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { store.perform { try await $0.resume(Array(selection)) } } label: { Label("Resume", systemImage: "play.fill") }
                .disabled(selection.isEmpty)
            Button { store.perform { try await $0.pause(Array(selection)) } } label: { Label("Pause", systemImage: "pause.fill") }
                .disabled(selection.isEmpty)
            Button { action = .delete(Array(selection)) } label: { Label("Delete", systemImage: "trash") }
                .disabled(selection.isEmpty)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Button {
                store.perform(store.server.useAltSpeedLimits ? "Normal speed limits" : "Alternative speed limits on") { try await $0.toggleAltSpeed() }
            } label: {
                Label("Alternative Speed", systemImage: store.server.useAltSpeedLimits ? "tortoise.fill" : "tortoise")
            }
            .tint(store.server.useAltSpeedLimits ? .orange : nil)
            .help("Toggle alternative speed limits (⇧⌘L)")
            Button { showLimits.toggle() } label: { Label("Speed Limits", systemImage: "speedometer") }
                .popover(isPresented: $showLimits, arrowEdge: .bottom) { SpeedLimitsPopover(store: store) }
            Button { showCategories = true } label: { Label("Categories", systemImage: "folder.badge.gearshape") }
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Button { app.showAddTorrent = true } label: { Label("Add Torrent", systemImage: "plus") }
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
        }
    }

    private var statusBar: some View {
        ViewThatFits(in: .horizontal) {
            statusContent(full: true)
            statusContent(full: false)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func statusContent(full: Bool) -> some View {
        HStack(spacing: 16) {
            Label(Fmt.speed(store.server.dlSpeed), systemImage: "arrow.down").foregroundStyle(.blue)
                .help("Limit: \(store.server.dlRateLimit > 0 ? Fmt.speed(store.server.dlRateLimit) : "∞")")
            Label(Fmt.speed(store.server.upSpeed), systemImage: "arrow.up").foregroundStyle(.green)
                .help("Limit: \(store.server.upRateLimit > 0 ? Fmt.speed(store.server.upRateLimit) : "∞")")
            if full {
                SpeedSparkline(samples: Array(store.samples.suffix(60)), showsAxis: false)
                    .frame(width: 140, height: 22)
            }
            Spacer(minLength: 8)
            if store.server.useAltSpeedLimits { Label(full ? "Alt. limits" : "", systemImage: "tortoise.fill").foregroundStyle(.orange) }
            Label(store.server.freeSpaceOnDisk.byteString + (full ? " free" : ""), systemImage: "internaldrive")
            if full {
                Label("DHT \(store.server.dhtNodes)", systemImage: "point.3.connected.trianglepath.dotted")
                Text("Session ↓\(store.server.dlData.byteString) ↑\(store.server.upData.byteString)").foregroundStyle(.secondary)
            }
            Image(systemName: store.server.connectionStatus == "connected" ? "network" : "network.slash")
                .foregroundStyle(store.server.connectionStatus == "connected" ? Color.green : .orange)
                .help(store.server.connectionStatus.capitalized)
        }
        .fixedSize(horizontal: full, vertical: false)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in AppModel.shared.handle(url: url) }
                }
            } else if p.canLoadObject(ofClass: String.self) {
                handled = true
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    guard let s, s.hasPrefix("magnet:") || s.hasPrefix("http"), let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                    Task { @MainActor in
                        if url.scheme == "magnet" { AppModel.shared.handle(url: url) } else {
                            AppModel.shared.pendingMagnet = url.absoluteString
                            AppModel.shared.showAddTorrent = true
                        }
                    }
                }
            }
        }
        return handled
    }
}

/// Type-erased primitive button style so we can switch glass/glassProminent dynamically.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct TorrentContextMenu: View {
    let store: TorrentStore
    let hashes: [String]
    @Binding var action: TorrentAction?

    private var torrents: [QBTorrent] { store.torrents.filter { hashes.contains($0.hash) } }

    var body: some View {
        if !hashes.isEmpty {
            Button("Resume", systemImage: "play") { store.perform { try await $0.resume(hashes) } }
            Button("Pause", systemImage: "pause") { store.perform { try await $0.pause(hashes) } }
            Button("Force Resume", systemImage: "forward") { store.perform { try await $0.setForceStart(hashes, true) } }
            Divider()
            Button("Delete…", systemImage: "trash") { action = .delete(hashes) }
            Divider()
            Menu("Category") {
                Button("New Category…") { action = .newCategory(hashes) }
                Button("Reset") { store.perform { try await $0.setCategory(hashes, "") } }
                Divider()
                ForEach(store.categories) { c in
                    Button(c.name) { store.perform("Category set to \(c.name)") { try await $0.setCategory(hashes, c.name) } }
                }
            }
            Menu("Tags") {
                Button("Add / Remove Tags…") { action = .tags(hashes) }
                Divider()
                ForEach(store.tags, id: \.self) { tag in
                    let all = torrents.allSatisfy { $0.tags.contains(tag) }
                    Button {
                        store.perform { all ? try await $0.removeTags(hashes, [tag]) : try await $0.addTags(hashes, [tag]) }
                    } label: {
                        if all { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                    }
                }
            }
            Button("Set Location…", systemImage: "folder") { action = .location(hashes) }
            if hashes.count == 1, let t = torrents.first {
                Button("Rename…", systemImage: "pencil") { action = .rename(t) }
            }
            Button("Speed Limits…", systemImage: "speedometer") { action = .limits(hashes) }
            Button("Share Limits…", systemImage: "arrow.up.circle") { action = .share(hashes) }
            Divider()
            Button("Force Recheck", systemImage: "checkmark.arrow.trianglehead.counterclockwise") { store.perform("Recheck started") { try await $0.recheck(hashes) } }
            Button("Force Reannounce", systemImage: "megaphone") { store.perform("Reannounced") { try await $0.reannounce(hashes) } }
            if store.server.queueing {
                Menu("Queue") {
                    Button("Move to Top") { store.perform { try await $0.move(hashes, .top) } }
                    Button("Move Up") { store.perform { try await $0.move(hashes, .up) } }
                    Button("Move Down") { store.perform { try await $0.move(hashes, .down) } }
                    Button("Move to Bottom") { store.perform { try await $0.move(hashes, .bottom) } }
                }
            }
            Menu("Options") {
                let t = torrents.first
                Toggle("Sequential Download", isOn: Binding(get: { t?.seqDl ?? false }, set: { _ in store.perform { try await $0.toggleSequential(hashes) } }))
                Toggle("First & Last Pieces First", isOn: Binding(get: { t?.firstLastPiecePrio ?? false }, set: { _ in store.perform { try await $0.toggleFirstLast(hashes) } }))
                Toggle("Automatic Torrent Management", isOn: Binding(get: { t?.autoTMM ?? false }, set: { v in store.perform { try await $0.setAutoManagement(hashes, v) } }))
                Toggle("Super Seeding", isOn: Binding(get: { t?.superSeeding ?? false }, set: { v in store.perform { try await $0.setSuperSeeding(hashes, v) } }))
            }
            Divider()
            Menu("Copy") {
                Button("Name") { copyToPasteboard(torrents.map(\.name).joined(separator: "\n")) }
                Button("Info Hash") { copyToPasteboard(hashes.joined(separator: "\n")) }
                Button("Magnet Link") { copyToPasteboard(torrents.map(\.magnetURI).joined(separator: "\n")) }
                Button("Content Path") { copyToPasteboard(torrents.map(\.contentPath).joined(separator: "\n")) }
            }
        }
    }
}
