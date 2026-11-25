import SwiftUI
import ArrcadeKit

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.dashboardCards) private var order = StoredList<DashboardCard>(DashboardCard.allCases)
    @AppStorage(Prefs.dashboardHidden) private var hidden = StoredList<DashboardCard>([])
    @State private var queue: [TaggedQueueItem] = []
    @State private var upcoming: [CalendarEntry] = []
    @State private var recent: [TaggedHistory] = []
    @State private var health: [(ServiceKind, ArrHealth)] = []
    @State private var disks: [ArrDiskSpace] = []
    @State private var pending: [SeerrRequest] = []
    @State private var path = NavigationPath()

    private var cards: [DashboardCard] {
        let all = order.items + DashboardCard.allCases.filter { !order.items.contains($0) }
        return all.filter { !hidden.items.contains($0) && isRelevant($0) }
    }

    private func isRelevant(_ c: DashboardCard) -> Bool {
        switch c {
        case .transfer: app.isConfigured(.qbittorrent)
        case .requests: app.isConfigured(.seerr)
        case .indexers: app.isConfigured(.prowlarr)
        case .queue, .upcoming, .recentlyAdded, .disk: app.isConfigured(.radarr) || app.isConfigured(.sonarr)
        case .health: true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    greeting
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)], spacing: 18) {
                        ForEach(cards) { card($0) }
                    }
                }
                .padding(22)
            }
            .navigationTitle("Dashboard")
            .navigationDestination(for: MovieRoute.self) { r in if let s = app.radarr { MovieDetailView(store: s, movieId: r.id) } }
            .navigationDestination(for: SeriesRoute.self) { r in if let s = app.sonarr { SeriesDetailView(store: s, seriesId: r.id) } }
            .navigationDestination(for: SeerrRoute.self) { r in if let s = app.seerr { SeerrMediaDetailView(store: s, tmdbId: r.tmdbId, isMovie: r.isMovie) } }
            .toolbar {
                ToolbarItem {
                    Menu {
                        ForEach(DashboardCard.allCases) { c in
                            Toggle(c.title, isOn: Binding(get: { !hidden.items.contains(c) }, set: { on in
                                if on { hidden.items.removeAll { $0 == c } } else { hidden.items.append(c) }
                            }))
                        }
                        Divider()
                        Button("Reset Layout") { order = StoredList(DashboardCard.allCases); hidden = StoredList([]) }
                    } label: { Label("Customize", systemImage: "slider.horizontal.3") }
                }
                ToolbarItem { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            }
        }
        .onAppear { app.torrents?.acquire() }
        .onDisappear { app.torrents?.release() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        let g = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return VStack(alignment: .leading, spacing: 4) {
            Text(g).font(.largeTitle.bold())
            Text(Date.now.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func card(_ c: DashboardCard) -> some View {
        switch c {
        case .transfer: transferCard
        case .health: healthCard
        case .queue: queueCard
        case .upcoming: upcomingCard
        case .requests: requestsCard
        case .recentlyAdded: recentCard
        case .disk: diskCard
        case .indexers: indexersCard
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var transferCard: some View {
        if let t = app.torrents {
            GlassCard(title: DashboardCard.transfer.title, symbol: DashboardCard.transfer.symbol, tint: .blue) {
                HStack(spacing: 12) {
                    StatTile(title: "Download", value: Fmt.speed(t.server.dlSpeed), symbol: "arrow.down.circle.fill", tint: .blue)
                    StatTile(title: "Upload", value: Fmt.speed(t.server.upSpeed), symbol: "arrow.up.circle.fill", tint: .green)
                }
                SpeedSparkline(samples: t.samples).frame(height: 90)
                HStack {
                    Text("\(t.downloading.count) downloading · \(t.activeCount) active · \(t.torrents.count) total").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { t.perform { try await $0.toggleAltSpeed() } } label: {
                        Label("Alt. Speed", systemImage: t.server.useAltSpeedLimits ? "tortoise.fill" : "tortoise")
                    }
                    .buttonStyle(.glass).tint(t.server.useAltSpeedLimits ? .orange : nil).controlSize(.small)
                    Button("Open") { app.selection = .torrents }.buttonStyle(.glass).controlSize(.small)
                }
                ForEach(t.downloading.sorted { $0.dlspeed > $1.dlspeed }.prefix(4)) { tor in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tor.name).font(.caption).lineLimit(1)
                        HStack {
                            LinearProgress(value: tor.progress, tint: tor.stateColor, height: 4)
                            Text("\(Fmt.percent(tor.progress)) · \(Fmt.speed(tor.dlspeed)) · \(Fmt.eta(tor.eta))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var healthCard: some View {
        GlassCard(title: DashboardCard.health.title, symbol: DashboardCard.health.symbol, tint: health.isEmpty ? .green : .orange) {
            HStack(spacing: 10) {
                ForEach(ServiceKind.allCases.filter { app.isConfigured($0) }) { k in
                    Image(systemName: k.symbol).foregroundStyle(k.tint)
                        .padding(8)
                        .glassEffect(.regular, in: .circle)
                        .help(k.displayName)
                }
            }
            if health.isEmpty {
                Label("All systems healthy", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                ForEach(Array(health.enumerated()), id: \.offset) { _, h in
                    HStack(alignment: .top) {
                        Image(systemName: h.1.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").foregroundStyle(h.1.isError ? .red : .orange)
                        VStack(alignment: .leading) {
                            Text(h.0.displayName).font(.caption.bold())
                            Text(h.1.message).font(.caption).lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    private var queueCard: some View {
        GlassCard(title: DashboardCard.queue.title, symbol: DashboardCard.queue.symbol, tint: .indigo) {
            if queue.isEmpty {
                Text("Nothing in the Radarr/Sonarr queue.").foregroundStyle(.secondary)
            } else {
                ForEach(queue.prefix(6)) { q in QueueItemRow(item: q.item, showsMedia: true, kind: q.kind) }
                if queue.count > 6 { Button("View all \(queue.count)") { app.selection = .activity }.buttonStyle(.link) }
            }
        }
    }

    private var upcomingCard: some View {
        GlassCard(title: DashboardCard.upcoming.title, symbol: DashboardCard.upcoming.symbol, tint: .cyan) {
            if upcoming.isEmpty {
                Text("Nothing scheduled this week.").foregroundStyle(.secondary)
            } else {
                ForEach(upcoming.prefix(8)) { e in
                    EntryLink(entry: e) {
                        HStack {
                            CalendarRow(entry: e)
                            Text(e.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 34)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("Open Calendar") { app.selection = .calendar }.buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var requestsCard: some View {
        if let s = app.seerr {
            GlassCard(title: DashboardCard.requests.title, symbol: DashboardCard.requests.symbol, tint: .orange) {
                if pending.isEmpty {
                    Label("No requests waiting for approval", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    ForEach(pending.prefix(5)) { r in
                        RequestCard(store: s, request: r) { Task { await load() } }
                    }
                }
                HStack {
                    if let c = s.counts { Text("\(c.processing ?? 0) processing · \(c.total ?? 0) total").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("All Requests") { app.selection = .requests }.buttonStyle(.link)
                }
            }
        }
    }

    private var recentCard: some View {
        GlassCard(title: DashboardCard.recentlyAdded.title, symbol: DashboardCard.recentlyAdded.symbol, tint: .green) {
            if recent.isEmpty { Text("No recent imports.").foregroundStyle(.secondary) }
            ForEach(recent.prefix(8)) { h in
                HStack {
                    Image(systemName: h.kind.symbol).foregroundStyle(h.kind.tint).frame(width: 20)
                    HistoryRow(record: h.record, showsMedia: true)
                }
            }
        }
    }

    private var diskCard: some View {
        GlassCard(title: DashboardCard.disk.title, symbol: DashboardCard.disk.symbol, tint: .teal) {
            if disks.isEmpty { Text("No disk information.").foregroundStyle(.secondary) }
            ForEach(disks) { d in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(d.label?.nilIfEmpty ?? d.path).font(.callout).lineLimit(1)
                        Spacer()
                        Text("\(d.freeSpace.byteString) free").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    LinearProgress(value: d.usedFraction, tint: d.usedFraction > 0.9 ? .red : d.usedFraction > 0.75 ? .orange : .teal, height: 7)
                }
            }
        }
    }

    @ViewBuilder
    private var indexersCard: some View {
        if let p = app.prowlarr {
            GlassCard(title: DashboardCard.indexers.title, symbol: DashboardCard.indexers.symbol, tint: .orange) {
                let enabled = p.indexers.filter(\.enable).count
                let failing = p.statuses.values.filter { ($0.disabledTill ?? .distantPast) > .now }.count
                HStack(spacing: 12) {
                    StatTile(title: "Enabled", value: "\(enabled)", symbol: "checkmark.circle", tint: .green)
                    StatTile(title: "Failing", value: "\(failing)", symbol: "xmark.circle", tint: failing > 0 ? .red : .secondary)
                }
                let top = p.indexers.sorted { (p.stats[$0.id]?.numberOfGrabs ?? 0) > (p.stats[$1.id]?.numberOfGrabs ?? 0) }.prefix(5)
                ForEach(Array(top)) { i in
                    HStack {
                        Text(i.displayName).font(.callout)
                        Spacer()
                        Text("\(p.stats[i.id]?.numberOfGrabs ?? 0) grabs · \(p.stats[i.id]?.averageResponseTime ?? 0) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Loading

    private func load() async {
        async let q: [TaggedQueueItem] = loadQueue()
        async let u: [CalendarEntry] = loadUpcoming()
        async let r: [TaggedHistory] = loadRecent()
        async let h: ([(ServiceKind, ArrHealth)], [ArrDiskSpace]) = loadHealth()
        async let p: [SeerrRequest] = (try? await app.seerr?.client.requests(filter: .pending, take: 10).results) ?? []
        let (qq, uu, rr, hh, pp) = await (q, u, r, h, p)
        queue = qq; upcoming = uu; recent = rr; health = hh.0; disks = hh.1; pending = pp
        await app.seerr?.loadBasics()
        if let prowlarr = app.prowlarr, prowlarr.indexers.isEmpty { await prowlarr.load() }
    }

    private func loadQueue() async -> [TaggedQueueItem] {
        var out: [TaggedQueueItem] = []
        if let c = app.radarr?.client, let r = try? await c.queue(pageSize: 20) { out += r.records.map { TaggedQueueItem(kind: .radarr, item: $0) } }
        if let c = app.sonarr?.client, let r = try? await c.queue(pageSize: 20) { out += r.records.map { TaggedQueueItem(kind: .sonarr, item: $0) } }
        return out
    }

    private func loadUpcoming() async -> [CalendarEntry] {
        let start = Calendar.current.startOfDay(for: .now), end = start.addingTimeInterval(7 * 86400)
        var out: [CalendarEntry] = []
        if let s = app.sonarr, let eps = try? await s.client.calendar(start: start, end: end, unmonitored: false) {
            out += eps.compactMap { e in
                guard let d = e.airDateUtc else { return nil }
                let series = e.series
                return CalendarEntry(id: "e\(e.id)", date: d, title: series?.title ?? "", subtitle: "\(e.code) · \(e.title ?? "")",
                                     kind: .episode(seriesId: e.seriesId), hasFile: e.hasFile ?? false, monitored: e.monitored,
                                     poster: series.map { s.posterURLs($0, width: 185) } ?? [], releaseType: nil)
            }
        }
        if let r = app.radarr, let movies = try? await r.client.calendar(start: start, end: end, unmonitored: false) {
            for m in movies {
                for (d, label) in [(m.digitalRelease, "Digital"), (m.physicalRelease, "Physical"), (m.inCinemas, "In Cinemas")] {
                    if let d, d >= start, d <= end {
                        out.append(CalendarEntry(id: "m\(m.id ?? 0)\(label)", date: d, title: m.title, subtitle: label, kind: .movie(m.id ?? 0),
                                                 hasFile: m.downloaded, monitored: m.monitored ?? true, poster: r.posterURLs(m, width: 185), releaseType: label))
                    }
                }
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private func loadRecent() async -> [TaggedHistory] {
        var out: [TaggedHistory] = []
        let imported: Set<String> = ["downloadFolderImported", "movieFolderImported", "seriesFolderImported"]
        if let c = app.radarr?.client, let h = try? await c.history(pageSize: 40) {
            out += h.records.filter { imported.contains($0.eventType) }.map { TaggedHistory(kind: .radarr, record: $0) }
        }
        if let c = app.sonarr?.client, let h = try? await c.history(pageSize: 40) {
            out += h.records.filter { imported.contains($0.eventType) }.map { TaggedHistory(kind: .sonarr, record: $0) }
        }
        return out.sorted { $0.record.date > $1.record.date }
    }

    private func loadHealth() async -> ([(ServiceKind, ArrHealth)], [ArrDiskSpace]) {
        var h: [(ServiceKind, ArrHealth)] = []
        var d: [ArrDiskSpace] = []
        let clients: [(ServiceKind, ArrClient?)] = [(.radarr, app.radarr?.client), (.sonarr, app.sonarr?.client), (.prowlarr, app.prowlarr?.client)]
        for (k, c) in clients {
            guard let c else { continue }
            h += ((try? await c.health()) ?? []).map { (k, $0) }
            if k != .prowlarr { d += (try? await c.diskSpace()) ?? [] }
        }
        var seen = Set<String>()
        d = d.filter { seen.insert($0.path).inserted && $0.totalSpace > 0 }
        return (h, d)
    }
}

extension CalendarEntry {
    var routeValue: AnyHashable {
        switch kind {
        case .movie(let id): AnyHashable(MovieRoute(id: id))
        case .episode(let sid): AnyHashable(SeriesRoute(id: sid))
        }
    }
}
