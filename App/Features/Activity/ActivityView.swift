import SwiftUI
import ArrcadeKit

/// Queue item tagged with the service it came from.
struct TaggedQueueItem: Identifiable {
    let kind: ServiceKind
    let item: ArrQueueItem
    var id: String { "\(kind.rawValue)-\(item.id)" }
}

struct TaggedHistory: Identifiable {
    let kind: ServiceKind
    let record: ArrHistoryRecord
    var id: String { "\(kind.rawValue)-\(record.id)" }
}

struct QueueItemRow: View {
    var item: ArrQueueItem
    var showsMedia: Bool
    var kind: ServiceKind?

    private var mediaTitle: String? {
        if let m = item.movie { return "\(m.title)" + (m.year.map { " (\(String($0)))" } ?? "") }
        if let s = item.series {
            if let e = item.episode { return "\(s.title) · \(e.code)" + (e.title.map { " · \($0)" } ?? "") }
            return s.title
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let kind { Image(systemName: kind.symbol).foregroundStyle(kind.tint).frame(width: 22) }
            VStack(alignment: .leading, spacing: 4) {
                if showsMedia, let mediaTitle { Text(mediaTitle).font(.callout.weight(.medium)).lineLimit(1) }
                Text(item.title ?? "Unknown").font(showsMedia ? .caption : .callout).foregroundStyle(showsMedia ? .secondary : .primary).lineLimit(1)
                HStack(spacing: 8) {
                    LinearProgress(value: item.progress, tint: item.hasWarning ? .orange : .blue).frame(maxWidth: 220)
                    Text(Fmt.percent(item.progress)).font(.caption.monospacedDigit())
                    Text(Fmt.bytes(item.size)).font(.caption).foregroundStyle(.secondary)
                    if let t = item.timeleft, item.progress < 1 { Text(t).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                if let msgs = item.statusMessages?.flatMap({ $0.messages ?? [] }), !msgs.isEmpty {
                    Text(msgs.joined(separator: " • ")).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if let e = item.errorMessage, !e.isEmpty {
                    Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Pill(text: (item.trackedDownloadState ?? item.status ?? "").humanized, color: item.hasWarning ? .orange : .blue)
                HStack(spacing: 4) {
                    if let q = item.quality?.name { Text(q) }
                    if let c = item.downloadClient { Text("· \(c)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActivityView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    @State private var queue: [TaggedQueueItem] = []
    @State private var history: [TaggedHistory] = []
    @State private var historyPage = 1
    @State private var state: LoadState = .idle
    @State private var removing: TaggedQueueItem?
    @State private var wantedKind = ServiceKind.radarr
    @State private var wantedCutoff = false

    var body: some View {
        Group {
            switch tab {
            case 0: queueList
            case 1: historyList
            default: WantedView(kind: $wantedKind, cutoff: $wantedCutoff)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $tab) {
                    Text("Queue (\(queue.count))").tag(0)
                    Text("History").tag(1)
                    Text("Wanted").tag(2)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        }
        .task {
            if !app.isConfigured(.radarr) { wantedKind = .sonarr }
            while !Task.isCancelled {
                await loadQueue()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task(id: tab) { if tab == 1 && history.isEmpty { await loadHistory(reset: true) } }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
        .sheet(item: $removing) { q in RemoveQueueSheet(item: q) { Task { await loadQueue() } } }
    }

    private func load() async {
        await loadQueue()
        if tab == 1 { await loadHistory(reset: true) }
    }

    private func loadQueue() async {
        if queue.isEmpty { state = .loading }
        var out: [TaggedQueueItem] = []
        var err: String?
        if let r = app.radarr {
            do { out += try await r.client.queue().records.map { TaggedQueueItem(kind: .radarr, item: $0) } } catch { err = error.localizedDescription }
        }
        if let s = app.sonarr {
            do { out += try await s.client.queue().records.map { TaggedQueueItem(kind: .sonarr, item: $0) } } catch { err = error.localizedDescription }
        }
        queue = out.sorted { ($0.item.estimatedCompletionTime ?? .distantFuture) < ($1.item.estimatedCompletionTime ?? .distantFuture) }
        state = err.map { .failed($0) } ?? .loaded
    }

    private func loadHistory(reset: Bool) async {
        if reset { historyPage = 1; history = [] }
        var out: [TaggedHistory] = []
        async let r = try? app.radarr?.client.history(page: historyPage, pageSize: 40).records
        async let s = try? app.sonarr?.client.history(page: historyPage, pageSize: 40).records
        let (rr, ss) = await (r, s)
        out += (rr ?? nil ?? []).map { TaggedHistory(kind: .radarr, record: $0) }
        out += (ss ?? nil ?? []).map { TaggedHistory(kind: .sonarr, record: $0) }
        history += out
        history.sort { $0.record.date > $1.record.date }
        historyPage += 1
    }

    private var queueList: some View {
        StateSwitch(state: state, isEmpty: queue.isEmpty && state != .loaded, retry: { Task { await loadQueue() } }) {
            if queue.isEmpty {
                ContentUnavailableView("Queue Is Empty", systemImage: "checkmark.circle", description: Text("Nothing is downloading through Radarr or Sonarr."))
            } else {
                List(queue) { q in
                    QueueItemRow(item: q.item, showsMedia: true, kind: q.kind)
                        .contextMenu {
                            Button("Remove…", systemImage: "trash") { removing = q }
                            if q.item.status?.lowercased() == "delay" {
                                Button("Grab Now", systemImage: "arrow.down.circle") {
                                    app.run("Grabbing") { try await client(q.kind)?.grabQueueItem(id: q.item.id); await loadQueue() }
                                }
                            }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { removing = q } }
                }
            }
        }
    }

    private func client(_ kind: ServiceKind) -> ArrClient? {
        kind == .radarr ? app.radarr?.client : app.sonarr?.client
    }

    private var historyList: some View {
        List {
            ForEach(history) { h in
                HStack {
                    Image(systemName: h.kind.symbol).foregroundStyle(h.kind.tint).frame(width: 22)
                    HistoryRow(record: h.record, showsMedia: true)
                }
                .onAppear { if h.id == history.last?.id { Task { await loadHistory(reset: false) } } }
            }
        }
        .overlay { if history.isEmpty { ProgressView() } }
    }
}

struct RemoveQueueSheet: View {
    let item: TaggedQueueItem
    var done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var removeFromClient = true
    @State private var blocklist = false
    @State private var skipRedownload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove from Queue").font(.title3.bold())
            Text(item.item.title ?? "").foregroundStyle(.secondary).lineLimit(3)
            Toggle("Remove from download client", isOn: $removeFromClient)
            Toggle("Add release to blocklist", isOn: $blocklist)
            if blocklist { Toggle("Skip automatic re-download", isOn: $skipRedownload) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Remove", role: .destructive) {
                    let (rc, bl, sk) = (removeFromClient, blocklist, skipRedownload)
                    let client: ArrClient? = item.kind == .radarr ? app.radarr?.client : app.sonarr?.client
                    let id = item.item.id
                    app.run("Removed from queue") {
                        try await client?.removeQueueItem(id: id, removeFromClient: rc, blocklist: bl, skipRedownload: sk)
                        done()
                    }
                    dismiss()
                }
                .buttonStyle(.glassProminent).tint(.red)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct WantedView: View {
    @Binding var kind: ServiceKind
    @Binding var cutoff: Bool
    @Environment(AppModel.self) private var app
    @State private var movies: [RadarrMovie] = []
    @State private var episodes: [SonarrEpisode] = []
    @State private var total = 0
    @State private var page = 1
    @State private var state: LoadState = .idle

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Service", selection: $kind) {
                    if app.isConfigured(.radarr) { Text("Movies").tag(ServiceKind.radarr) }
                    if app.isConfigured(.sonarr) { Text("Episodes").tag(ServiceKind.sonarr) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("Type", selection: $cutoff) {
                    Text("Missing").tag(false); Text("Cutoff Unmet").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text("\(total) \(cutoff ? "cutoff unmet" : "missing") \(kind == .radarr ? "movies" : "episodes")").foregroundStyle(.secondary)
                Spacer()
                Button {
                    app.run("Search started") {
                        if kind == .radarr {
                            try await app.radarr?.client.command(cutoff ? "CutoffUnmetMoviesSearch" : "MissingMoviesSearch")
                        } else {
                            try await app.sonarr?.client.command(cutoff ? "CutoffUnmetEpisodeSearch" : "MissingEpisodeSearch", ["monitored": true])
                        }
                    }
                } label: { Label("Search All", systemImage: "magnifyingglass") }
                .buttonStyle(.glassProminent)
            }
            .padding()
            StateSwitch(state: state, isEmpty: movies.isEmpty && episodes.isEmpty && state != .loaded, retry: { Task { await load(reset: true) } }) {
                List {
                    if kind == .radarr {
                        ForEach(movies, id: \.stableID) { m in
                            HStack(spacing: 12) {
                                RemoteImage(app.radarr?.posterURLs(m, width: 92) ?? [], pixelWidth: 80).frame(width: 34, height: 51).clipShape(.rect(cornerRadius: 4))
                                VStack(alignment: .leading) {
                                    Text(m.title).font(.callout.weight(.medium))
                                    Text("\(m.year.map(String.init) ?? "") · \(app.radarr?.profileName(m.qualityProfileId) ?? "") · \(m.movieFile?.quality?.name ?? "No file")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { app.run("Searching \(m.title)") { try await app.radarr?.client.searchMovies(ids: [m.id ?? 0]) } } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.glass)
                            }
                            .onAppear { if m.id == movies.last?.id { Task { await load(reset: false) } } }
                        }
                    } else {
                        ForEach(episodes) { e in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("\(e.series?.title ?? "") · \(e.code)").font(.callout.weight(.medium))
                                    Text("\(e.title ?? "") · aired \(Fmt.date(e.airDateUtc))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { app.run("Searching \(e.code)") { try await app.sonarr?.client.searchEpisodes(ids: [e.id]) } } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.glass)
                            }
                            .onAppear { if e.id == episodes.last?.id { Task { await load(reset: false) } } }
                        }
                    }
                }
            }
        }
        .task(id: "\(kind.rawValue)\(cutoff)") { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if reset { page = 1; movies = []; episodes = []; total = 0; state = .loading }
        guard reset || (movies.count + episodes.count) < total else { return }
        do {
            if kind == .radarr, let c = app.radarr?.client {
                let p = try await (cutoff ? c.wantedCutoff(page: page) : c.wantedMissing(page: page))
                movies += p.records; total = p.totalRecords
            } else if let c = app.sonarr?.client {
                let p = try await (cutoff ? c.wantedCutoff(page: page) : c.wantedMissing(page: page))
                episodes += p.records; total = p.totalRecords
            }
            page += 1
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
