import SwiftUI
import PilothouseKit

enum MovieFilter: String, CaseIterable, Identifiable {
    case all, monitored, unmonitored, missing, downloaded, upcoming, cutoffUnmet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All Movies"
        case .monitored: "Monitored"
        case .unmonitored: "Unmonitored"
        case .missing: "Missing"
        case .downloaded: "Downloaded"
        case .upcoming: "Upcoming"
        case .cutoffUnmet: "Cutoff Unmet"
        }
    }
    func matches(_ m: RadarrMovie) -> Bool {
        switch self {
        case .all: true
        case .monitored: m.monitored == true
        case .unmonitored: m.monitored == false
        case .missing: !m.downloaded && m.monitored == true && m.isAvailable == true
        case .downloaded: m.downloaded
        case .upcoming: !m.downloaded && m.isAvailable == false
        case .cutoffUnmet: m.movieFile?.qualityCutoffNotMet == true
        }
    }
}

enum MovieSort: String, CaseIterable, Identifiable {
    case title, year, added, release, size, rating, runtime
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: "Title"
        case .year: "Year"
        case .added: "Date Added"
        case .release: "Release Date"
        case .size: "Size on Disk"
        case .rating: "Rating"
        case .runtime: "Runtime"
        }
    }
}

struct MoviesView: View {
    @Bindable var store: RadarrStore
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.movieLayout) private var layout = LibraryLayout.grid
    @AppStorage(Prefs.movieSort) private var sort = MovieSort.title
    @AppStorage(Prefs.movieSortAsc) private var ascending = true
    @AppStorage(Prefs.movieFilter) private var filter = MovieFilter.all
    @AppStorage(Prefs.posterSize) private var posterSize = PosterSize.medium
    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var showAdd = false
    @State private var deleting: RadarrMovie?
    @State private var tableSelection = Set<RadarrMovie.ID>()
    @State private var tableSort = [KeyPathComparator(\RadarrMovie.sortKey)]

    private var movies: [RadarrMovie] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var list = store.movies.filter { filter.matches($0) }
        if !q.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(q) || ($0.originalTitle ?? "").localizedCaseInsensitiveContains(q) || String($0.year ?? 0) == q }
        }
        list.sort { a, b in
            let r: Bool
            switch sort {
            case .title: r = a.sortKey.localizedStandardCompare(b.sortKey) == .orderedAscending
            case .year: r = (a.year ?? 0, a.sortKey) < (b.year ?? 0, b.sortKey)
            case .added: r = (a.added ?? .distantPast) < (b.added ?? .distantPast)
            case .release: r = (a.primaryRelease ?? .distantFuture) < (b.primaryRelease ?? .distantFuture)
            case .size: r = a.fileSize < b.fileSize
            case .rating: r = a.bestRating < b.bestRating
            case .runtime: r = (a.runtime ?? 0) < (b.runtime ?? 0)
            }
            return ascending ? r : !r
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            StateSwitch(state: store.state, isEmpty: store.movies.isEmpty, retry: { Task { await store.load(force: true) } }) {
                let list = movies
                Group {
                    if list.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else if layout == .grid {
                        grid(list)
                    } else {
                        table(list)
                    }
                }
            }
            .navigationTitle("Movies")
            .navigationSubtitle("\(movies.count) of \(store.movies.count)")
            .searchable(text: $search, placement: .toolbar, prompt: "Filter movies")
            .toolbar { toolbar }
            .navigationDestination(for: MovieRoute.self) { route in
                MovieDetailView(store: store, movieId: route.id)
            }
        }
        .task { await store.load() }
        .focusedSceneValue(\.refreshAction) { Task { await store.load(force: true) } }
        .sheet(isPresented: $showAdd) { AddMovieSheet(store: store) }
        .sheet(item: $deleting) { m in
            DeleteMediaSheet(title: m.title, exclusionLabel: "Add list exclusion (prevent re-adding from lists)") { files, excl in
                app.run("Deleted \(m.title)") {
                    try await store.client.deleteMovie(id: m.id!, deleteFiles: files, addExclusion: excl)
                    store.removeLocal(movieId: m.id!)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Picker("Filter", selection: $filter) {
                    ForEach(MovieFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(MovieSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Order", selection: $ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.inline)
                if layout == .grid {
                    Divider()
                    Picker("Poster Size", selection: $posterSize) {
                        ForEach(PosterSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            Picker("Layout", selection: $layout) {
                ForEach(LibraryLayout.allCases) { Label($0.rawValue.capitalized, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Menu {
                Button("Search All Missing") { app.run("Searching all missing movies") { try await store.client.command("MissingMoviesSearch") } }
                Button("Search Cutoff Unmet") { app.run("Searching cutoff unmet movies") { try await store.client.command("CutoffUnmetMoviesSearch") } }
                Divider()
                Button("Update Library") { app.run("Refreshing all movies") { try await store.client.command("RefreshMovie") } }
                Button("RSS Sync") { app.run("RSS sync started") { try await store.client.command("RssSync") } }
            } label: {
                Label("Tasks", systemImage: "bolt")
            }
            Button { Task { await store.load(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button { showAdd = true } label: { Label("Add Movie", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func grid(_ list: [RadarrMovie]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: posterSize.width, maximum: posterSize.width + 24), spacing: 18)], spacing: 22) {
                ForEach(list, id: \.stableID) { m in
                    NavigationLink(value: MovieRoute(id: m.id ?? 0)) {
                        PosterTile(urls: store.posterURLs(m, width: Int(posterSize.width * 2)), title: m.title,
                                   subtitle: subtitle(m), width: posterSize.width, dimmed: m.monitored == false) {
                            StatusDot(color: m.statusColor)
                                .padding(4)
                                .glassEffect(.regular, in: .circle)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(m) }
                }
            }
            .padding(20)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func subtitle(_ m: RadarrMovie) -> String {
        var parts: [String] = []
        if let y = m.year, y > 0 { parts.append(String(y)) }
        if m.downloaded { parts.append(m.movieFile?.quality?.name ?? "Downloaded") } else { parts.append(m.statusLabel) }
        return parts.joined(separator: " · ")
    }

    private func table(_ list: [RadarrMovie]) -> some View {
        Table(list.sorted(using: tableSort), selection: $tableSelection, sortOrder: $tableSort) {
            TableColumn("Title", value: \.sortKey) { m in
                HStack(spacing: 8) {
                    StatusDot(color: m.statusColor)
                    RemoteImage(store.posterURLs(m, width: 92), pixelWidth: 60).frame(width: 22, height: 33).clipShape(.rect(cornerRadius: 3))
                    Text(m.title).lineLimit(1)
                }
            }
            .width(min: 220, ideal: 320)
            TableColumn("Year", value: \.yearValue) { m in Text(m.year.map(String.init) ?? "—").monospacedDigit() }.width(50)
            TableColumn("Profile") { m in Text(store.profileName(m.qualityProfileId)) }.width(min: 80, ideal: 110)
            TableColumn("Status", value: \.statusLabel) { m in Pill(text: m.statusLabel, color: m.statusColor) }.width(min: 90, ideal: 110)
            TableColumn("Quality") { m in Text(m.movieFile?.quality?.name ?? "—") }.width(min: 80, ideal: 110)
            TableColumn("Size", value: \.fileSize) { m in Text(m.fileSize > 0 ? m.fileSize.byteString : "—").monospacedDigit() }.width(75)
            TableColumn("Added", value: \.addedValue) { m in Text(Fmt.date(m.added)) }.width(95)
            TableColumn("Release", value: \.releaseValue) { m in Text(Fmt.date(m.primaryRelease)) }.width(95)
        }
        .contextMenu(forSelectionType: RadarrMovie.ID.self) { ids in
            if let id = ids.first ?? nil, let m = store.movie(id: id) { contextMenu(m) }
        } primaryAction: { ids in
            if let id = ids.first ?? nil { path.append(MovieRoute(id: id)) }
        }
    }

    @ViewBuilder
    private func contextMenu(_ m: RadarrMovie) -> some View {
        if let id = m.id {
            Button("Automatic Search", systemImage: "magnifyingglass") {
                app.run("Searching for \(m.title)") { try await store.client.searchMovies(ids: [id]) }
            }
            Button(m.monitored == true ? "Unmonitor" : "Monitor", systemImage: m.monitored == true ? "bookmark.slash" : "bookmark") {
                app.run(m.monitored == true ? "Unmonitored" : "Monitored") {
                    try await store.client.setMonitored(movieIds: [id], monitored: !(m.monitored ?? false))
                    await store.reload(movieId: id)
                }
            }
            Button("Refresh & Scan", systemImage: "arrow.clockwise") {
                app.run("Refreshing \(m.title)") { try await store.client.refreshMovies(ids: [id]) }
            }
            Divider()
            if let base = store.client.http.baseURL {
                Button("Open in Radarr", systemImage: "safari") { openWeb(base.absoluteString + "/movie/\(m.titleSlug ?? String(m.tmdbId))") }
            }
            Button("Open on TMDB") { openWeb("https://www.themoviedb.org/movie/\(m.tmdbId)") }
            if let imdb = m.imdbId { Button("Open on IMDb") { openWeb("https://www.imdb.com/title/\(imdb)") } }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = m }
        }
    }
}

struct MovieRoute: Hashable {
    let id: Int
    var instance: UUID? = nil
}

nonisolated extension RadarrMovie {
    var sortKey: String { sortTitle ?? title.lowercased() }
    var yearValue: Int { year ?? 0 }
    var addedValue: Date { added ?? .distantPast }
    var releaseValue: Date { primaryRelease ?? .distantFuture }
    var bestRating: Double { ratings?.imdb?.value ?? ratings?.tmdb?.value ?? 0 }
}
