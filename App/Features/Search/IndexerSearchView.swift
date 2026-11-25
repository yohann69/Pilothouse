import SwiftUI
import PilothouseKit

struct IndexerSearchView: View {
    let store: ProwlarrStore
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.searchDefaultType) private var type = ProwlarrSearchType.search
    @State private var query = ""
    @State private var results: [ProwlarrSearchResult] = []
    @State private var state: LoadState = .idle
    @State private var selectedIndexers = Set<Int>()
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\ProwlarrSearchResult.seedersValue, order: .reverse)]
    @State private var filter = ""
    @State private var lastQuery = ""
    @State private var searchTask: Task<Void, Never>?

    private var rows: [ProwlarrSearchResult] {
        results.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Group {
                if state.isLoading {
                    LoadingView(label: "Searching \(selectedIndexers.isEmpty ? "all" : "\(selectedIndexers.count)") indexers…")
                } else if let e = state.error {
                    ErrorView(message: e) { runSearch() }
                } else if results.isEmpty {
                    ContentUnavailableView(lastQuery.isEmpty ? "Search Your Indexers" : "No Results",
                                           systemImage: "magnifyingglass",
                                           description: Text(lastQuery.isEmpty ? "Results come from every indexer configured in Prowlarr." : "Nothing found for “\(lastQuery)”."))
                } else {
                    table
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle("Search")
        .navigationSubtitle(results.isEmpty ? "Prowlarr" : "\(rows.count) results")
        .task { if store.indexers.isEmpty { await store.load() } }
        .toolbar {
            ToolbarItemGroup {
                Button { grabSelected() } label: { Label("Grab with Prowlarr", systemImage: "arrow.down.circle") }
                    .disabled(selection.isEmpty)
                if app.isConfigured(.qbittorrent) {
                    Menu {
                        Button("No Category") { sendToQB(category: nil) }
                        ForEach(app.torrents?.categories ?? []) { c in Button(c.name) { sendToQB(category: c.name) } }
                    } label: { Label("Send to qBittorrent", systemImage: "arrow.up.arrow.down.circle") }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }

    private var searchBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search all indexers", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .onSubmit { runSearch() }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                Picker("Type", selection: $type) {
                    ForEach(ProwlarrSearchType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Menu {
                    Button("All Indexers") { selectedIndexers = [] }
                    Divider()
                    ForEach(store.indexers.filter(\.enable)) { i in
                        Toggle(i.displayName, isOn: Binding(get: { selectedIndexers.contains(i.id) }, set: { on in
                            if on { selectedIndexers.insert(i.id) } else { selectedIndexers.remove(i.id) }
                        }))
                    }
                } label: {
                    Label(selectedIndexers.isEmpty ? "All Indexers" : "\(selectedIndexers.count) Indexers", systemImage: "list.bullet.rectangle")
                }
                .menuStyle(.button).buttonStyle(.glass).fixedSize()
                Button("Search") { runSearch() }
                    .buttonStyle(.glassProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("") { (r: ProwlarrSearchResult) in
                    Image(systemName: r.isTorrent ? "arrow.down.doc" : "newspaper").foregroundStyle(r.isTorrent ? .green : .blue)
                }
                .width(22)
                TableColumn("Age", value: \ProwlarrSearchResult.ageValue) { r in Text(Fmt.age(hours: r.ageHours)).monospacedDigit() }.width(50)
                TableColumn("Title", value: \ProwlarrSearchResult.title) { r in Text(r.title).lineLimit(2).help(r.title) }.width(min: 280, ideal: 480)
                TableColumn("Indexer", value: \ProwlarrSearchResult.indexerValue) { r in Text(r.indexer ?? "") }.width(min: 70, ideal: 100)
                TableColumn("Size", value: \ProwlarrSearchResult.sizeValue) { r in Text(Fmt.bytes(r.size)).monospacedDigit() }.width(75)
                TableColumn("Grabs", value: \ProwlarrSearchResult.grabsValue) { r in Text(r.grabs.map(String.init) ?? "").monospacedDigit() }.width(50)
                TableColumn("Peers", value: \ProwlarrSearchResult.seedersValue) { r in
                    if r.isTorrent {
                        Text("\(r.seeders ?? 0)/\(r.leechers ?? 0)").monospacedDigit()
                            .foregroundStyle((r.seeders ?? 0) > 10 ? .green : (r.seeders ?? 0) > 0 ? .orange : .red)
                    }
                }
                .width(65)
                TableColumn("Categories") { (r: ProwlarrSearchResult) in Text(r.categoryNames).lineLimit(1).foregroundStyle(.secondary) }.width(min: 80, ideal: 140)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let items = results.filter { ids.contains($0.id) }
                Button("Grab with Prowlarr") { grab(items) }
                if app.isConfigured(.qbittorrent) {
                    Menu("Send to qBittorrent") {
                        Button("No Category") { send(items, category: nil) }
                        ForEach(app.torrents?.categories ?? []) { c in Button(c.name) { send(items, category: c.name) } }
                    }
                }
                Divider()
                if let r = items.first {
                    if let m = r.magnetUrl ?? r.downloadUrl { Button("Copy Link") { copyToPasteboard(m) } }
                    if let i = r.infoUrl, let u = URL(string: i) { Link("Open Indexer Page", destination: u) }
                    Button("Copy Title") { copyToPasteboard(r.title) }
                }
            } primaryAction: { ids in
                grab(results.filter { ids.contains($0.id) })
            }
            HStack {
                TextField("Filter results", text: $filter).textFieldStyle(.roundedBorder).frame(width: 240)
                Spacer()
                Text("Double-click to grab with Prowlarr").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        lastQuery = q
        state = .loading
        selection = []
        let t = type, ids = Array(selectedIndexers)
        searchTask = Task {
            do {
                let r = try await store.client.search(query: q, type: t, indexerIds: ids, categories: t.defaultCategories, limit: 100)
                if !Task.isCancelled { results = r; state = .loaded }
            } catch {
                if !Task.isCancelled { state = .failed(error.localizedDescription) }
            }
        }
    }

    private func grabSelected() { grab(results.filter { selection.contains($0.id) }) }

    private func grab(_ items: [ProwlarrSearchResult]) {
        for r in items {
            app.run("Grabbed “\(r.title)”") { try await store.client.grab(r) }
        }
    }

    private func sendToQB(category: String?) { send(results.filter { selection.contains($0.id) }, category: category) }

    private func send(_ items: [ProwlarrSearchResult], category: String?) {
        guard let qb = app.torrents else { return }
        let urls = items.compactMap { $0.magnetUrl ?? $0.downloadUrl }
        guard !urls.isEmpty else { app.flash("These results have no download link.", .error); return }
        var o = QBAddOptions()
        o.category = category
        qb.perform("Sent \(urls.count) to qBittorrent") { try await $0.add(urls: urls, options: o) }
    }
}

nonisolated extension ProwlarrSearchResult {
    var seedersValue: Int { seeders ?? -1 }
    var sizeValue: Int64 { size ?? 0 }
    var ageValue: Double { ageMinutes ?? 0 }
    var grabsValue: Int { grabs ?? 0 }
    var indexerValue: String { indexer ?? "" }
}

struct IndexersView: View {
    let store: ProwlarrStore
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    @State private var history: [ProwlarrHistoryRecord] = []
    @State private var apps: [ProwlarrApplication] = []
    @State private var testing = Set<Int>()
    @State private var selection: ProwlarrIndexer.ID?

    var body: some View {
        Group {
            switch tab {
            case 0: indexers
            case 1: historyList
            default: appsList
            }
        }
        .navigationTitle("Indexers")
        .navigationSubtitle("\(store.indexers.filter(\.enable).count) of \(store.indexers.count) enabled")
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $tab) {
                    Text("Indexers").tag(0); Text("History").tag(1); Text("Apps").tag(2)
                }
                .pickerStyle(.segmented)
            }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup {
                Button { app.run("All indexers tested") { _ = try await store.client.testAllIndexers(); await store.load() } } label: {
                    Label("Test All", systemImage: "checkmark.shield")
                }
                Button { app.run("App sync started") { try await store.client.syncApplications() } } label: {
                    Label("Sync Apps", systemImage: "arrow.triangle.2.circlepath")
                }
                Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .task { await reload() }
        .focusedSceneValue(\.refreshAction) { Task { await reload() } }
    }

    private func reload() async {
        await store.load()
        history = (try? await store.client.history(pageSize: 100).records) ?? []
        apps = (try? await store.client.applications()) ?? []
    }

    private var indexers: some View {
        StateSwitch(state: store.state, isEmpty: store.indexers.isEmpty, retry: { Task { await store.load() } }) {
            Table(store.indexers, selection: $selection) {
                TableColumn("On") { (i: ProwlarrIndexer) in
                    Toggle("", isOn: Binding(get: { i.enable }, set: { v in
                        app.run(v ? "Enabled \(i.displayName)" : "Disabled \(i.displayName)") {
                            try await store.client.setIndexer(id: i.id, enabled: v); await store.load()
                        }
                    }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.green)
                }
                .width(44)
                TableColumn("Name") { (i: ProwlarrIndexer) in
                    HStack {
                        StatusDot(color: store.statuses[i.id]?.disabledTill.map { $0 > .now ? Color.red : .green } ?? (i.enable ? .green : .gray))
                        Text(i.displayName)
                    }
                    .help(i.description ?? "")
                }
                .width(min: 140, ideal: 200)
                TableColumn("Protocol") { (i: ProwlarrIndexer) in Text((i.protocol ?? "").capitalized) }.width(70)
                TableColumn("Privacy") { (i: ProwlarrIndexer) in Pill(text: (i.privacy ?? "").capitalized, color: i.privacy == "private" ? .purple : i.privacy == "public" ? .green : .orange) }.width(85)
                TableColumn("Priority") { (i: ProwlarrIndexer) in Text("\(i.priority ?? 25)").monospacedDigit() }.width(55)
                TableColumn("Queries") { (i: ProwlarrIndexer) in Text("\(store.stats[i.id]?.numberOfQueries ?? 0)").monospacedDigit() }.width(60)
                TableColumn("Grabs") { (i: ProwlarrIndexer) in Text("\(store.stats[i.id]?.numberOfGrabs ?? 0)").monospacedDigit() }.width(50)
                TableColumn("Failures") { (i: ProwlarrIndexer) in
                    let f = (store.stats[i.id]?.numberOfFailedQueries ?? 0) + (store.stats[i.id]?.numberOfFailedGrabs ?? 0)
                    Text("\(f)").monospacedDigit().foregroundStyle(f > 0 ? .orange : .secondary)
                }
                .width(60)
                TableColumn("Avg Response") { (i: ProwlarrIndexer) in Text("\(store.stats[i.id]?.averageResponseTime ?? 0) ms").monospacedDigit() }.width(90)
                TableColumn("") { (i: ProwlarrIndexer) in
                    if testing.contains(i.id) { ProgressView().controlSize(.small) } else {
                        Button("Test") { test(i) }.buttonStyle(.glass).controlSize(.small)
                    }
                }
                .width(60)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if let id = ids.first, let i = store.indexers.first(where: { $0.id == id }) {
                    Button("Test") { test(i) }
                    Button(i.enable ? "Disable" : "Enable") {
                        app.run { try await store.client.setIndexer(id: id, enabled: !i.enable); await store.load() }
                    }
                    Menu("Priority") {
                        ForEach([1, 5, 10, 25, 40, 50], id: \.self) { p in
                            Button("\(p)") { app.run("Priority set") { try await store.client.setIndexerPriority(id: id, priority: p); await store.load() } }
                        }
                    }
                    if let u = i.indexerUrls?.first { Button("Open Site") { openWeb(u) } }
                }
            }
        }
    }

    private func test(_ i: ProwlarrIndexer) {
        testing.insert(i.id)
        Task {
            do {
                try await store.client.testIndexer(id: i.id)
                app.flash("\(i.displayName) is working")
            } catch {
                app.flash("\(i.displayName): \(error.localizedDescription)", .error)
            }
            testing.remove(i.id)
        }
    }

    private var historyList: some View {
        List(history) { h in
            HStack {
                Image(systemName: h.successful == false ? "xmark.circle.fill" : h.eventType == "releaseGrabbed" ? "arrow.down.circle.fill" : "magnifyingglass.circle")
                    .foregroundStyle(h.successful == false ? .red : h.eventType == "releaseGrabbed" ? .green : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.value("grabTitle") ?? h.value("query") ?? h.eventType ?? "").lineLimit(1)
                    Text("\(store.indexers.first { $0.id == h.indexerId }?.displayName ?? "") · \(h.value("source") ?? "") · \(h.value("queryType") ?? h.eventType ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.relative(h.date)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appsList: some View {
        List(apps) { a in
            HStack {
                Image(systemName: "app.connected.to.app.below.fill").foregroundStyle(.tint)
                Text(a.name ?? a.implementation ?? "")
                Spacer()
                Pill(text: a.syncLevel ?? "", color: .indigo)
            }
        }
        .overlay { if apps.isEmpty { ContentUnavailableView("No Applications", systemImage: "app.dashed") } }
    }
}
