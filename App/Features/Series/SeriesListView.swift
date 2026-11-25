import SwiftUI
import PilothouseKit

enum SeriesFilter: String, CaseIterable, Identifiable {
    case all, monitored, unmonitored, continuing, ended, missing, complete
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All Series"
        case .monitored: "Monitored"
        case .unmonitored: "Unmonitored"
        case .continuing: "Continuing"
        case .ended: "Ended"
        case .missing: "Missing Episodes"
        case .complete: "Complete"
        }
    }
    func matches(_ s: SonarrSeries) -> Bool {
        let have = s.statistics?.episodeFileCount ?? 0, total = s.statistics?.episodeCount ?? 0
        switch self {
        case .all: return true
        case .monitored: return s.monitored == true
        case .unmonitored: return s.monitored == false
        case .continuing: return s.isContinuing
        case .ended: return !s.isContinuing
        case .missing: return have < total
        case .complete: return total > 0 && have >= total
        }
    }
}

enum SeriesSort: String, CaseIterable, Identifiable {
    case title, year, added, nextAiring, previousAiring, size, episodes, network
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: "Title"
        case .year: "Year"
        case .added: "Date Added"
        case .nextAiring: "Next Airing"
        case .previousAiring: "Previous Airing"
        case .size: "Size on Disk"
        case .episodes: "Episode Progress"
        case .network: "Network"
        }
    }
}

struct SeriesRoute: Hashable {
    let id: Int
    var instance: UUID? = nil
}

struct SeriesListView: View {
    @Bindable var store: SonarrStore
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.seriesLayout) private var layout = LibraryLayout.grid
    @AppStorage(Prefs.seriesSort) private var sort = SeriesSort.title
    @AppStorage(Prefs.seriesSortAsc) private var ascending = true
    @AppStorage(Prefs.seriesFilter) private var filter = SeriesFilter.all
    @AppStorage(Prefs.posterSize) private var posterSize = PosterSize.medium
    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var showAdd = false
    @State private var deleting: SonarrSeries?
    @State private var tableSelection = Set<SonarrSeries.ID>()

    private var list: [SonarrSeries] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var l = store.series.filter { filter.matches($0) }
        if !q.isEmpty { l = l.filter { $0.title.localizedCaseInsensitiveContains(q) || ($0.network ?? "").localizedCaseInsensitiveContains(q) } }
        l.sort { a, b in
            let r: Bool
            switch sort {
            case .title: r = a.sortKey.localizedStandardCompare(b.sortKey) == .orderedAscending
            case .year: r = (a.year ?? 0) < (b.year ?? 0)
            case .added: r = (a.added ?? .distantPast) < (b.added ?? .distantPast)
            case .nextAiring: r = (a.nextAiring ?? .distantFuture) < (b.nextAiring ?? .distantFuture)
            case .previousAiring: r = (a.previousAiring ?? .distantPast) < (b.previousAiring ?? .distantPast)
            case .size: r = (a.statistics?.sizeOnDisk ?? 0) < (b.statistics?.sizeOnDisk ?? 0)
            case .episodes: r = a.percent < b.percent
            case .network: r = (a.network ?? "") < (b.network ?? "")
            }
            return ascending ? r : !r
        }
        return l
    }

    var body: some View {
        NavigationStack(path: $path) {
            StateSwitch(state: store.state, isEmpty: store.series.isEmpty, retry: { Task { await store.load(force: true) } }) {
                let items = list
                if items.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if layout == .grid {
                    grid(items)
                } else {
                    table(items)
                }
            }
            .navigationTitle("Series")
            .navigationSubtitle("\(list.count) of \(store.series.count)")
            .searchable(text: $search, placement: .toolbar, prompt: "Filter series")
            .toolbar { toolbar }
            .navigationDestination(for: SeriesRoute.self) { SeriesDetailView(store: store, seriesId: $0.id) }
        }
        .task { await store.load() }
        .focusedSceneValue(\.refreshAction) { Task { await store.load(force: true) } }
        .sheet(isPresented: $showAdd) { AddSeriesSheet(store: store) }
        .sheet(item: $deleting) { s in
            DeleteMediaSheet(title: s.title, exclusionLabel: "Add import list exclusion") { files, excl in
                app.run("Deleted \(s.title)") {
                    try await store.client.deleteSeries(id: s.id!, deleteFiles: files, addExclusion: excl)
                    store.removeLocal(seriesId: s.id!)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Picker("Filter", selection: $filter) { ForEach(SeriesFilter.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline)
            } label: { Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
            Menu {
                Picker("Sort By", selection: $sort) { ForEach(SeriesSort.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline)
                Divider()
                Picker("Order", selection: $ascending) { Text("Ascending").tag(true); Text("Descending").tag(false) }.pickerStyle(.inline)
                if layout == .grid {
                    Divider()
                    Picker("Poster Size", selection: $posterSize) { ForEach(PosterSize.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline)
                }
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            Picker("Layout", selection: $layout) {
                ForEach(LibraryLayout.allCases) { Label($0.rawValue.capitalized, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Menu {
                Button("Search All Missing") { app.run("Searching missing episodes") { try await store.client.command("MissingEpisodeSearch", ["monitored": true]) } }
                Button("Search Cutoff Unmet") { app.run("Searching cutoff unmet") { try await store.client.command("CutoffUnmetEpisodeSearch", ["monitored": true]) } }
                Divider()
                Button("Update All Series") { app.run("Refreshing all series") { try await store.client.command("RefreshSeries") } }
                Button("RSS Sync") { app.run("RSS sync started") { try await store.client.command("RssSync") } }
            } label: { Label("Tasks", systemImage: "bolt") }
            Button { Task { await store.load(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button { showAdd = true } label: { Label("Add Series", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func grid(_ items: [SonarrSeries]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: posterSize.width, maximum: posterSize.width + 24), spacing: 18)], spacing: 22) {
                ForEach(items, id: \.stableID) { s in
                    NavigationLink(value: SeriesRoute(id: s.id ?? 0)) {
                        VStack(alignment: .leading, spacing: 4) {
                            PosterTile(urls: store.posterURLs(s, width: Int(posterSize.width * 2)), title: s.title,
                                       subtitle: subtitle(s), width: posterSize.width, symbol: "tv", dimmed: s.monitored == false) {
                                StatusDot(color: s.statusColor).padding(4).glassEffect(.regular, in: .circle)
                            }
                            LinearProgress(value: s.percent, tint: s.statusColor, height: 3).frame(width: posterSize.width)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(s) }
                }
            }
            .padding(20)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func subtitle(_ s: SonarrSeries) -> String {
        if let next = s.nextAiring { return "Next: " + next.formatted(.relative(presentation: .named)) }
        return "\(s.episodeSummary) episodes · \(s.network ?? (s.year.map(String.init) ?? ""))"
    }

    private func table(_ items: [SonarrSeries]) -> some View {
        Table(items, selection: $tableSelection) {
            TableColumn("Title") { s in
                HStack(spacing: 8) {
                    StatusDot(color: s.statusColor)
                    RemoteImage(store.posterURLs(s, width: 92), pixelWidth: 60).frame(width: 22, height: 33).clipShape(.rect(cornerRadius: 3))
                    Text(s.title).lineLimit(1)
                }
            }
            .width(min: 220, ideal: 300)
            TableColumn("Network") { s in Text(s.network ?? "—") }.width(min: 70, ideal: 100)
            TableColumn("Profile") { s in Text(store.profileName(s.qualityProfileId)) }.width(min: 70, ideal: 100)
            TableColumn("Seasons") { s in Text("\(s.statistics?.seasonCount ?? 0)").monospacedDigit() }.width(55)
            TableColumn("Episodes") { s in
                HStack {
                    LinearProgress(value: s.percent, tint: s.statusColor).frame(width: 60)
                    Text(s.episodeSummary).monospacedDigit().font(.caption)
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Next Airing") { s in Text(s.nextAiring.map { Fmt.dateTime($0) } ?? "—") }.width(min: 100, ideal: 140)
            TableColumn("Size") { s in Text(Fmt.bytes(s.statistics?.sizeOnDisk)).monospacedDigit() }.width(75)
            TableColumn("Status") { s in Pill(text: s.isContinuing ? "Continuing" : "Ended", color: s.isContinuing ? .green : .secondary) }.width(90)
        }
        .contextMenu(forSelectionType: SonarrSeries.ID.self) { ids in
            if let id = ids.first ?? nil, let s = store.series(id: id) { contextMenu(s) }
        } primaryAction: { ids in
            if let id = ids.first ?? nil { path.append(SeriesRoute(id: id)) }
        }
    }

    @ViewBuilder
    private func contextMenu(_ s: SonarrSeries) -> some View {
        if let id = s.id {
            Button("Search Monitored", systemImage: "magnifyingglass") { app.run("Searching \(s.title)") { try await store.client.searchSeries(id: id) } }
            Button(s.monitored == true ? "Unmonitor" : "Monitor", systemImage: "bookmark") {
                app.run(s.monitored == true ? "Unmonitored" : "Monitored") {
                    let target = !(s.monitored ?? false)
                    try await store.client.update(seriesId: id) { $0["monitored"] = .bool(target) }
                    await store.reload(seriesId: id)
                }
            }
            Button("Refresh & Scan", systemImage: "arrow.clockwise") { app.run("Refreshing \(s.title)") { try await store.client.refreshSeries(id: id) } }
            Divider()
            if let base = store.client.http.baseURL, let slug = s.titleSlug {
                Button("Open in Sonarr", systemImage: "safari") { openWeb(base.absoluteString + "/series/\(slug)") }
            }
            if let tvdb = s.tvdbId { Button("Open on TheTVDB") { openWeb("https://thetvdb.com/?tab=series&id=\(tvdb)") } }
            if let imdb = s.imdbId, !imdb.isEmpty { Button("Open on IMDb") { openWeb("https://www.imdb.com/title/\(imdb)") } }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = s }
        }
    }
}

nonisolated extension SonarrSeries {
    var sortKey: String { sortTitle ?? title.lowercased() }
}
