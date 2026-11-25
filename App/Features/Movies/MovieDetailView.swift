import SwiftUI
import PilothouseKit

struct MovieDetailView: View {
    @Bindable var store: RadarrStore
    let movieId: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var files: [RadarrMovieFile] = []
    @State private var history: [ArrHistoryRecord] = []
    @State private var queue: [ArrQueueItem] = []
    @State private var showReleases = false
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var deletingFile: RadarrMovieFile?

    private var movie: RadarrMovie? { store.movie(id: movieId) }

    var body: some View {
        Group {
            if let m = movie {
                content(m)
            } else {
                LoadingView()
            }
        }
        .task { await load() }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
    }

    private func load() async {
        if movie == nil { await store.load() }
        await store.reload(movieId: movieId)
        async let f = try? store.client.movieFiles(movieId: movieId)
        async let h = try? store.client.history(movieId: movieId)
        async let q = try? store.client.queue()
        let (files, history, queue) = await (f, h, q)
        self.files = files ?? []
        self.history = (history ?? []).sorted { $0.date > $1.date }
        self.queue = (queue?.records ?? []).filter { $0.movieId == movieId }
    }

    @ViewBuilder
    private func content(_ m: RadarrMovie) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackdropHeader(backdrop: store.fanartURLs(m), poster: store.posterURLs(m, width: 400)) {
                    header(m)
                }
                VStack(alignment: .leading, spacing: 20) {
                    actions(m)
                    if let overview = m.overview, !overview.isEmpty {
                        Text(overview).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: 820, alignment: .leading)
                    }
                    ForEach(queue) { q in
                        GlassCard(title: "Downloading", symbol: "arrow.down.circle", tint: .blue) {
                            QueueItemRow(item: q, showsMedia: false)
                        }
                    }
                    info(m)
                    if !files.isEmpty {
                        GlassCard(title: "Files", symbol: "doc", tint: .teal) {
                            ForEach(files) { f in
                                MediaFileView(path: f.path ?? f.relativePath, size: f.size, quality: f.quality, languages: f.languages,
                                              mediaInfo: f.mediaInfo, releaseGroup: f.releaseGroup, added: f.dateAdded,
                                              customFormatScore: f.customFormatScore, cutoffNotMet: f.qualityCutoffNotMet) {
                                    deletingFile = f
                                }
                            }
                        }
                    }
                    GlassCard(title: "History", symbol: "clock.arrow.circlepath", tint: .orange) {
                        if history.isEmpty {
                            Text("No history yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(history.prefix(30)) { HistoryRow(record: $0) }
                        }
                    }
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(m.title)
        .toolbar {
            ToolbarItemGroup {
                Button { showReleases = true } label: { Label("Interactive Search", systemImage: "person.fill.questionmark") }
                Button { showEdit = true } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                Button { showDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .sheet(isPresented: $showReleases) {
            ReleasesSheet(title: "\(m.title) (\(m.year.map(String.init) ?? ""))",
                          load: { try await store.client.releases(movieId: movieId) },
                          grab: { try await store.client.grab(release: $0, movieId: movieId) })
        }
        .sheet(isPresented: $showEdit) { EditMovieSheet(store: store, movie: m) }
        .sheet(isPresented: $showDelete) {
            DeleteMediaSheet(title: m.title, exclusionLabel: "Add list exclusion (prevent re-adding from lists)") { files, excl in
                app.run("Deleted \(m.title)") {
                    try await store.client.deleteMovie(id: movieId, deleteFiles: files, addExclusion: excl)
                    store.removeLocal(movieId: movieId)
                    dismiss()
                }
            }
        }
        .confirmationDialog("Delete this file from disk?", isPresented: Binding(get: { deletingFile != nil }, set: { if !$0 { deletingFile = nil } }), presenting: deletingFile) { f in
            Button("Delete File", role: .destructive) {
                app.run("File deleted") {
                    try await store.client.deleteMovieFile(id: f.id)
                    await load()
                }
            }
        } message: { f in Text(f.relativePath ?? f.path ?? "") }
    }

    private func header(_ m: RadarrMovie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(m.title).font(.largeTitle.bold()).lineLimit(2).shadow(radius: 4)
            HStack(spacing: 8) {
                if let y = m.year { Text(String(y)) }
                if let r = Fmt.runtime(m.runtime) { Text("·"); Text(r) }
                if let c = m.certification, !c.isEmpty { Text("·"); Text(c) }
                if let studio = m.studio, !studio.isEmpty { Text("·"); Text(studio) }
            }
            .font(.headline).opacity(0.9)
            if let genres = m.genres, !genres.isEmpty {
                Text(genres.joined(separator: ", ")).font(.subheadline).opacity(0.8)
            }
            HStack(spacing: 8) {
                Pill(text: m.statusLabel, color: m.statusColor)
                if let r = m.ratings?.imdb?.value, r > 0 { RatingBadge(source: "IMDb", value: String(format: "%.1f", r), color: .yellow) }
                if let r = m.ratings?.tmdb?.value, r > 0 { RatingBadge(source: "TMDB", value: "\(Int(r * 10))%", color: .teal) }
                if let r = m.ratings?.rottenTomatoes?.value, r > 0 { RatingBadge(source: "RT", value: "\(Int(r))%", color: .red) }
                if let r = m.ratings?.metacritic?.value, r > 0 { RatingBadge(source: "MC", value: "\(Int(r))", color: .green) }
            }
        }
    }

    private func actions(_ m: RadarrMovie) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    app.run("Searching for \(m.title)") { try await store.client.searchMovies(ids: [movieId]) }
                } label: { Label("Automatic Search", systemImage: "magnifyingglass") }
                    .buttonStyle(.glassProminent)
                Button { showReleases = true } label: { Label("Interactive", systemImage: "person.fill.questionmark") }
                    .buttonStyle(.glass)
                Button {
                    app.run(m.monitored == true ? "Unmonitored" : "Monitored") {
                        try await store.client.setMonitored(movieIds: [movieId], monitored: !(m.monitored ?? false))
                        await store.reload(movieId: movieId)
                    }
                } label: {
                    Label(m.monitored == true ? "Monitored" : "Unmonitored", systemImage: m.monitored == true ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.glass)
                .tint(m.monitored == true ? .accentColor : .gray)
                Button {
                    app.run("Refresh & scan started") {
                        try await store.client.refreshMovies(ids: [movieId])
                        try? await Task.sleep(for: .seconds(2))
                        await load()
                    }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glass)
                Menu {
                    Button("Rename Files") { app.run("Renaming files") { try await store.client.renameMovies(ids: [movieId]) } }
                    Button("Rescan Disk") { app.run("Rescanning") { try await store.client.rescanMovie(id: movieId) } }
                    Divider()
                    if let t = m.youTubeTrailerId, !t.isEmpty { Button("Watch Trailer") { openWeb("https://www.youtube.com/watch?v=\(t)") } }
                    Button("Open on TMDB") { openWeb("https://www.themoviedb.org/movie/\(m.tmdbId)") }
                    if let imdb = m.imdbId { Button("Open on IMDb") { openWeb("https://www.imdb.com/title/\(imdb)") } }
                    if let base = store.client.http.baseURL {
                        Button("Open in Radarr") { openWeb(base.absoluteString + "/movie/\(m.titleSlug ?? String(m.tmdbId))") }
                    }
                    if let path = m.path { Button("Copy Path") { copyToPasteboard(path) } }
                } label: { Label("More", systemImage: "ellipsis") }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .fixedSize()
            }
        }
    }

    private func info(_ m: RadarrMovie) -> some View {
        GlassCard(title: "Information", symbol: "info.circle") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow { infoCell("Quality Profile", store.profileName(m.qualityProfileId)); infoCell("Minimum Availability", RadarrAvailability(rawValue: m.minimumAvailability ?? "")?.label ?? m.minimumAvailability ?? "—") }
                GridRow { infoCell("In Cinemas", Fmt.date(m.inCinemas)); infoCell("Digital Release", Fmt.date(m.digitalRelease)) }
                GridRow { infoCell("Physical Release", Fmt.date(m.physicalRelease)); infoCell("Added", Fmt.date(m.added)) }
                GridRow { infoCell("Size on Disk", m.fileSize > 0 ? m.fileSize.byteString : "—"); infoCell("Original Language", m.originalLanguage?.name ?? "—") }
                GridRow { infoCell("Path", m.path ?? "—"); infoCell("Tags", store.tagNames(m.tags).joined(separator: ", ").nilIfEmpty ?? "—") }
                if let c = m.collection?.title { GridRow { infoCell("Collection", c); Color.clear } }
            }
        }
    }

    private func infoCell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditMovieSheet: View {
    @Bindable var store: RadarrStore
    let movie: RadarrMovie
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var monitored = true
    @State private var profile = 0
    @State private var availability = "released"
    @State private var path = ""
    @State private var moveFiles = true
    @State private var tags = Set<Int>()
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Toggle("Monitored", isOn: $monitored)
                Picker("Quality Profile", selection: $profile) {
                    ForEach(store.profiles) { Text($0.name).tag($0.id) }
                }
                Picker("Minimum Availability", selection: $availability) {
                    ForEach(RadarrAvailability.allCases) { Text($0.label).tag($0.rawValue) }
                }
                TextField("Path", text: $path)
                if path != (movie.path ?? "") {
                    Toggle("Move existing files to new path", isOn: $moveFiles)
                }
                LabeledContent("Tags") {
                    TagPicker(all: store.tags, selected: $tags) { label in
                        try? await store.client.createTag(label).also { t in store.tags.append(t) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(saving)
            }
            .padding()
        }
        .frame(width: 520, height: 470)
        .navigationTitle("Edit \(movie.title)")
        .onAppear {
            monitored = movie.monitored ?? true
            profile = movie.qualityProfileId ?? store.profiles.first?.id ?? 0
            availability = movie.minimumAvailability ?? "released"
            path = movie.path ?? ""
            tags = Set(movie.tags ?? [])
        }
    }

    private func save() {
        guard let id = movie.id else { return }
        saving = true
        let pathChanged = path != (movie.path ?? "")
        let (mon, prof, avail, newPath, tagList, move) = (monitored, profile, availability, path, Array(tags), moveFiles && pathChanged)
        Task {
            do {
                _ = try await store.client.update(movieId: id, moveFiles: move) { raw in
                    raw["monitored"] = .bool(mon)
                    raw["qualityProfileId"] = JSONValue(prof)
                    raw["minimumAvailability"] = .string(avail)
                    raw["path"] = .string(newPath)
                    raw["tags"] = JSONValue(tagList)
                }
                await store.reload(movieId: id)
                app.flash("Saved \(movie.title)")
                dismiss()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            saving = false
        }
    }
}

extension Optional {
    /// Run a side effect on the wrapped value and return it.
    func also(_ f: (Wrapped) -> Void) -> Wrapped? {
        if let v = self { f(v) }
        return self
    }
}

extension ArrTag {
    func also(_ f: (ArrTag) -> Void) -> ArrTag { f(self); return self }
}
