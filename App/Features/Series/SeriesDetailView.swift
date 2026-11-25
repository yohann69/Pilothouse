import SwiftUI
import PilothouseKit

struct SeriesDetailView: View {
    @Bindable var store: SonarrStore
    let seriesId: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var episodes: [SonarrEpisode] = []
    @State private var files: [Int: SonarrEpisodeFile] = [:]
    @State private var queue: [ArrQueueItem] = []
    @State private var expanded: Set<Int> = []
    @State private var releaseTarget: ReleaseTarget?
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var showHistory = false
    @State private var selectedEpisode: SonarrEpisode?

    struct ReleaseTarget: Identifiable {
        var id: String
        var title: String
        var episodeId: Int?
        var season: Int?
    }

    private var series: SonarrSeries? { store.series(id: seriesId) }

    var body: some View {
        Group {
            if let s = series { content(s) } else { LoadingView() }
        }
        .task { await load(initial: true) }
        .focusedSceneValue(\.refreshAction) { Task { await load(initial: false) } }
    }

    private func load(initial: Bool) async {
        if series == nil { await store.load() }
        await store.reload(seriesId: seriesId)
        async let e = try? store.client.episodes(seriesId: seriesId)
        async let f = try? store.client.episodeFiles(seriesId: seriesId)
        async let q = try? store.client.queue()
        let (eps, fs, qs) = await (e, f, q)
        episodes = eps ?? []
        files = Dictionary((fs ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        queue = (qs?.records ?? []).filter { $0.seriesId == seriesId }
        if initial, expanded.isEmpty, let latest = series?.seasons?.map(\.seasonNumber).max() { expanded = [latest] }
    }

    @ViewBuilder
    private func content(_ s: SonarrSeries) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackdropHeader(backdrop: store.fanartURLs(s), poster: store.posterURLs(s, width: 400), posterSymbol: "tv") {
                    header(s)
                }
                VStack(alignment: .leading, spacing: 18) {
                    actions(s)
                    if let o = s.overview, !o.isEmpty {
                        Text(o).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: 820, alignment: .leading)
                    }
                    if !queue.isEmpty {
                        GlassCard(title: "Downloading", symbol: "arrow.down.circle", tint: .blue) {
                            ForEach(queue) { QueueItemRow(item: $0, showsMedia: true) }
                        }
                    }
                    info(s)
                    ForEach((s.seasons ?? []).sorted { $0.seasonNumber > $1.seasonNumber }) { season in
                        seasonCard(s, season)
                    }
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(s.title)
        .toolbar {
            ToolbarItemGroup {
                Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                Button { showEdit = true } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                Button { showDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .sheet(item: $releaseTarget) { t in
            ReleasesSheet(title: t.title, load: {
                if let e = t.episodeId { return try await store.client.releases(episodeId: e) }
                return try await store.client.releases(seriesId: seriesId, seasonNumber: t.season ?? 1)
            }, grab: { r in
                try await store.client.grab(release: r)
            })
        }
        .sheet(item: $selectedEpisode) { e in
            EpisodeSheet(store: store, episode: e, file: e.episodeFileId.flatMap { files[$0] }) {
                Task { await load(initial: false) }
            } interactive: {
                releaseTarget = ReleaseTarget(id: "e\(e.id)", title: "\(s.title) \(e.code) · \(e.title ?? "")", episodeId: e.id)
            }
        }
        .sheet(isPresented: $showEdit) { EditSeriesSheet(store: store, series: s) }
        .sheet(isPresented: $showHistory) { SeriesHistorySheet(store: store, series: s) }
        .sheet(isPresented: $showDelete) {
            DeleteMediaSheet(title: s.title, exclusionLabel: "Add import list exclusion") { files, excl in
                app.run("Deleted \(s.title)") {
                    try await store.client.deleteSeries(id: seriesId, deleteFiles: files, addExclusion: excl)
                    store.removeLocal(seriesId: seriesId)
                    dismiss()
                }
            }
        }
    }

    private func header(_ s: SonarrSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.title).font(.largeTitle.bold()).lineLimit(2).shadow(radius: 4)
            HStack(spacing: 8) {
                if let y = s.year { Text(String(y)) }
                if let n = s.network { Text("·"); Text(n) }
                if let r = Fmt.runtime(s.runtime) { Text("·"); Text(r) }
                if let c = s.certification { Text("·"); Text(c) }
            }
            .font(.headline).opacity(0.9)
            if let g = s.genres, !g.isEmpty { Text(g.joined(separator: ", ")).font(.subheadline).opacity(0.8) }
            HStack(spacing: 8) {
                Pill(text: s.isContinuing ? "Continuing" : "Ended", color: s.isContinuing ? .green : .gray)
                Pill(text: "\(s.episodeSummary) episodes", color: s.statusColor)
                if let r = s.ratings?.value, r > 0 { RatingBadge(source: "★", value: String(format: "%.1f", r), color: .yellow) }
                if let next = s.nextAiring { Pill(text: "Next \(Fmt.dateTime(next))", color: .blue, symbol: "calendar") }
            }
        }
    }

    private func actions(_ s: SonarrSeries) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    app.run("Searching monitored episodes") { try await store.client.searchSeries(id: seriesId) }
                } label: { Label("Search Monitored", systemImage: "magnifyingglass") }
                    .buttonStyle(.glassProminent)
                Button {
                    app.run(s.monitored == true ? "Unmonitored" : "Monitored") {
                        let target = !(s.monitored ?? false)
                        try await store.client.update(seriesId: seriesId) { $0["monitored"] = .bool(target) }
                        await store.reload(seriesId: seriesId)
                    }
                } label: { Label(s.monitored == true ? "Monitored" : "Unmonitored", systemImage: s.monitored == true ? "bookmark.fill" : "bookmark") }
                    .buttonStyle(.glass)
                    .tint(s.monitored == true ? .accentColor : .gray)
                Button {
                    app.run("Refresh & scan started") {
                        try await store.client.refreshSeries(id: seriesId)
                        try? await Task.sleep(for: .seconds(2))
                        await load(initial: false)
                    }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glass)
                Menu {
                    Button("Rename Files") { app.run("Renaming") { try await store.client.renameSeries(ids: [seriesId]) } }
                    Button("Rescan Disk") { app.run("Rescanning") { try await store.client.rescanSeries(id: seriesId) } }
                    Divider()
                    if let base = store.client.http.baseURL, let slug = s.titleSlug {
                        Button("Open in Sonarr") { openWeb(base.absoluteString + "/series/\(slug)") }
                    }
                    if let tvdb = s.tvdbId { Button("Open on TheTVDB") { openWeb("https://thetvdb.com/?tab=series&id=\(tvdb)") } }
                    if let imdb = s.imdbId, !imdb.isEmpty { Button("Open on IMDb") { openWeb("https://www.imdb.com/title/\(imdb)") } }
                    if let p = s.path { Button("Copy Path") { copyToPasteboard(p) } }
                } label: { Label("More", systemImage: "ellipsis") }
                    .menuStyle(.button).buttonStyle(.glass).fixedSize()
            }
        }
    }

    private func info(_ s: SonarrSeries) -> some View {
        GlassCard(title: "Information", symbol: "info.circle") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow { cell("Quality Profile", store.profileName(s.qualityProfileId)); cell("Series Type", (s.seriesType ?? "standard").capitalized) }
                GridRow { cell("Path", s.path ?? "—"); cell("Size on Disk", Fmt.bytes(s.statistics?.sizeOnDisk)) }
                GridRow { cell("Season Folders", s.seasonFolder == true ? "Yes" : "No"); cell("Monitor New Seasons", (s.monitorNewItems ?? "all").capitalized) }
                GridRow { cell("Added", Fmt.date(s.added)); cell("Tags", store.tagNames(s.tags).joined(separator: ", ").nilIfEmpty ?? "—") }
            }
        }
    }

    private func cell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seasonCard(_ s: SonarrSeries, _ season: SonarrSeason) -> some View {
        let eps = episodes.filter { $0.seasonNumber == season.seasonNumber }.sorted { $0.episodeNumber > $1.episodeNumber }
        let isOpen = expanded.contains(season.seasonNumber)
        let stats = season.statistics
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    app.run(season.monitored ? "Season unmonitored" : "Season monitored") {
                        try await store.client.setSeasonMonitored(seriesId: seriesId, seasonNumber: season.seasonNumber, monitored: !season.monitored)
                        await load(initial: false)
                    }
                } label: {
                    Image(systemName: season.monitored ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(season.monitored ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(season.monitored ? "Unmonitor season" : "Monitor season")
                Button {
                    withAnimation(.snappy) {
                        if isOpen { expanded.remove(season.seasonNumber) } else { expanded.insert(season.seasonNumber) }
                    }
                } label: {
                    HStack {
                        Text(season.seasonNumber == 0 ? "Specials" : "Season \(season.seasonNumber)").font(.headline)
                        let have = stats?.episodeFileCount ?? 0, total = stats?.episodeCount ?? 0
                        Pill(text: "\(have)/\(total)", color: total > 0 && have >= total ? .green : (have > 0 ? .orange : .secondary))
                        if let size = stats?.sizeOnDisk, size > 0 { Text(size.byteString).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0)).foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button {
                    app.run("Searching season \(season.seasonNumber)") { try await store.client.searchSeason(seriesId: seriesId, seasonNumber: season.seasonNumber) }
                } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("Search season")
                Button {
                    releaseTarget = ReleaseTarget(id: "s\(season.seasonNumber)", title: "\(s.title) — Season \(season.seasonNumber)", season: season.seasonNumber)
                } label: { Image(systemName: "person.fill.questionmark") }
                    .buttonStyle(.borderless).help("Interactive season search")
            }
            .padding(14)
            if isOpen {
                Divider().padding(.horizontal, 14)
                LazyVStack(spacing: 0) {
                    ForEach(eps) { e in
                        episodeRow(e)
                        if e.id != eps.last?.id { Divider().padding(.leading, 50) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func episodeRow(_ e: SonarrEpisode) -> some View {
        let file = e.episodeFileId.flatMap { files[$0] }
        let downloading = queue.first { $0.episodeId == e.id }
        return HStack(spacing: 12) {
            Button {
                app.run(e.monitored ? "Episode unmonitored" : "Episode monitored") {
                    try await store.client.setEpisodesMonitored(ids: [e.id], monitored: !e.monitored)
                    await load(initial: false)
                }
            } label: {
                Image(systemName: e.monitored ? "bookmark.fill" : "bookmark").foregroundStyle(e.monitored ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            Text("\(e.episodeNumber)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title ?? "TBA").lineLimit(1)
                Text(e.airDateUtc.map { Fmt.dateTime($0) } ?? "TBA").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let downloading {
                HStack(spacing: 6) {
                    LinearProgress(value: downloading.progress, tint: .blue).frame(width: 70)
                    Text(Fmt.percent(downloading.progress)).font(.caption.monospacedDigit())
                }
            } else if let file {
                Pill(text: file.quality?.name ?? "Downloaded", color: file.qualityCutoffNotMet == true ? .orange : .green)
            } else if !e.aired {
                Pill(text: "Unaired", color: .blue)
            } else {
                Pill(text: "Missing", color: e.monitored ? .red : .secondary)
            }
            Button {
                app.run("Searching \(e.code)") { try await store.client.searchEpisodes(ids: [e.id]) }
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Automatic search")
            Button {
                releaseTarget = ReleaseTarget(id: "e\(e.id)", title: "\(series?.title ?? "") \(e.code) · \(e.title ?? "")", episodeId: e.id)
            } label: { Image(systemName: "person.fill.questionmark") }
                .buttonStyle(.borderless).help("Interactive search")
            Button { selectedEpisode = e } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Details")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .onTapGesture(count: 2) { selectedEpisode = e }
    }
}

struct EpisodeSheet: View {
    @Bindable var store: SonarrStore
    let episode: SonarrEpisode
    let file: SonarrEpisodeFile?
    var changed: () -> Void
    var interactive: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var history: [ArrHistoryRecord] = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.code) · \(episode.title ?? "TBA")").font(.title2.bold())
                    Text("Aired \(Fmt.dateTime(episode.airDateUtc))" + (episode.runtime.flatMap(Fmt.runtime).map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let o = episode.overview, !o.isEmpty { Text(o).textSelection(.enabled) }
                    GlassEffectContainer {
                        HStack {
                            Button { app.run("Searching \(episode.code)") { try await store.client.searchEpisodes(ids: [episode.id]) } } label: {
                                Label("Automatic Search", systemImage: "magnifyingglass")
                            }.buttonStyle(.glassProminent)
                            Button { dismiss(); interactive() } label: { Label("Interactive Search", systemImage: "person.fill.questionmark") }
                                .buttonStyle(.glass)
                            Button {
                                app.run(episode.monitored ? "Unmonitored" : "Monitored") {
                                    try await store.client.setEpisodesMonitored(ids: [episode.id], monitored: !episode.monitored)
                                    changed()
                                    dismiss()
                                }
                            } label: { Label(episode.monitored ? "Unmonitor" : "Monitor", systemImage: "bookmark") }
                                .buttonStyle(.glass)
                        }
                    }
                    if let file {
                        GlassCard(title: "File", symbol: "doc") {
                            MediaFileView(path: file.path ?? file.relativePath, size: file.size, quality: file.quality, languages: file.languages,
                                          mediaInfo: file.mediaInfo, releaseGroup: file.releaseGroup, added: file.dateAdded,
                                          customFormatScore: file.customFormatScore, cutoffNotMet: file.qualityCutoffNotMet) {
                                confirmDelete = true
                            }
                        }
                    }
                    GlassCard(title: "History", symbol: "clock.arrow.circlepath") {
                        if history.isEmpty { Text("No history.").foregroundStyle(.secondary) }
                        ForEach(history) { HistoryRow(record: $0) }
                    }
                }
                .padding()
            }
        }
        .frame(width: 680, height: 600)
        .task { history = (try? await store.client.history(episodeId: episode.id).records) ?? [] }
        .confirmationDialog("Delete this episode file from disk?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                guard let file else { return }
                app.run("File deleted") {
                    try await store.client.deleteEpisodeFile(id: file.id)
                    changed()
                    dismiss()
                }
            }
        }
    }
}

struct SeriesHistorySheet: View {
    @Bindable var store: SonarrStore
    let series: SonarrSeries
    @Environment(\.dismiss) private var dismiss
    @State private var history: [ArrHistoryRecord] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List(history) { HistoryRow(record: $0, showsMedia: true) }
                .overlay { if !loaded { ProgressView() } else if history.isEmpty { ContentUnavailableView("No History", systemImage: "clock") } }
                .navigationTitle("History — \(series.title)")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(width: 720, height: 560)
        .task {
            var h = (try? await store.client.history(seriesId: series.id!)) ?? []
            h.sort { $0.date > $1.date }
            for i in h.indices where h[i].series == nil { h[i].series = series }
            history = h
            loaded = true
        }
    }
}

struct EditSeriesSheet: View {
    @Bindable var store: SonarrStore
    let series: SonarrSeries
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var monitored = true
    @State private var monitorNew = "all"
    @State private var seasonFolder = true
    @State private var profile = 0
    @State private var seriesType = "standard"
    @State private var path = ""
    @State private var moveFiles = true
    @State private var tags = Set<Int>()
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Toggle("Monitored", isOn: $monitored)
                Picker("Monitor New Seasons", selection: $monitorNew) {
                    Text("All Seasons").tag("all")
                    Text("None").tag("none")
                }
                Toggle("Use Season Folders", isOn: $seasonFolder)
                Picker("Quality Profile", selection: $profile) { ForEach(store.profiles) { Text($0.name).tag($0.id) } }
                Picker("Series Type", selection: $seriesType) {
                    Text("Standard").tag("standard"); Text("Daily").tag("daily"); Text("Anime").tag("anime")
                }
                TextField("Path", text: $path)
                if path != (series.path ?? "") { Toggle("Move existing files", isOn: $moveFiles) }
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
        .frame(width: 520, height: 520)
        .onAppear {
            monitored = series.monitored ?? true
            monitorNew = series.monitorNewItems ?? "all"
            seasonFolder = series.seasonFolder ?? true
            profile = series.qualityProfileId ?? store.profiles.first?.id ?? 0
            seriesType = series.seriesType ?? "standard"
            path = series.path ?? ""
            tags = Set(series.tags ?? [])
        }
    }

    private func save() {
        guard let id = series.id else { return }
        saving = true
        let pathChanged = path != (series.path ?? "")
        let v = (monitored, monitorNew, seasonFolder, profile, seriesType, path, Array(tags))
        let move = moveFiles && pathChanged
        Task {
            do {
                _ = try await store.client.update(seriesId: id, moveFiles: move) { raw in
                    raw["monitored"] = .bool(v.0)
                    raw["monitorNewItems"] = .string(v.1)
                    raw["seasonFolder"] = .bool(v.2)
                    raw["qualityProfileId"] = JSONValue(v.3)
                    raw["seriesType"] = .string(v.4)
                    raw["path"] = .string(v.5)
                    raw["tags"] = JSONValue(v.6)
                }
                await store.reload(seriesId: id)
                app.flash("Saved \(series.title)")
                dismiss()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            saving = false
        }
    }
}
