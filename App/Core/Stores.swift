import SwiftUI
import PilothouseKit

enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
    var isLoading: Bool { self == .loading }
    var error: String? { if case .failed(let e) = self { return e }; return nil }
}

// MARK: - Radarr

@Observable
final class RadarrStore {
    let client: RadarrClient
    var movies: [RadarrMovie] = []
    var profiles: [ArrQualityProfile] = []
    var rootFolders: [ArrRootFolder] = []
    var tags: [ArrTag] = []
    var state: LoadState = .idle
    var lastLoaded: Date?

    let config: ServiceConfig
    var name: String { config.name }

    init(config: ServiceConfig) {
        self.config = config
        client = RadarrClient(config: config)
    }

    func load(force: Bool = false) async {
        if !force, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 30, !movies.isEmpty { return }
        if movies.isEmpty { state = .loading }
        do {
            async let m = client.movies()
            async let p = client.qualityProfiles()
            async let r = client.rootFolders()
            async let t = client.tags()
            let (movies, profiles, roots, tags) = try await (m, p, r, t)
            self.movies = movies
            self.profiles = profiles
            self.rootFolders = roots
            self.tags = tags
            state = .loaded
            lastLoaded = .now
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reload(movieId: Int) async {
        guard let m = try? await client.movie(id: movieId) else { return }
        if let i = movies.firstIndex(where: { $0.id == movieId }) { movies[i] = m } else { movies.append(m) }
    }

    func removeLocal(movieId: Int) { movies.removeAll { $0.id == movieId } }

    func movie(id: Int) -> RadarrMovie? { movies.first { $0.id == id } }
    func movie(tmdbId: Int) -> RadarrMovie? { movies.first { $0.tmdbId == tmdbId } }
    func profileName(_ id: Int?) -> String { profiles.first { $0.id == id }?.name ?? "—" }
    func tagNames(_ ids: [Int]?) -> [String] { (ids ?? []).compactMap { id in tags.first { $0.id == id }?.label } }

    func posterURLs(_ m: RadarrMovie, width: Int = 342) -> [URL?] {
        imageURLs(m.images?.image("poster"), width: width, remoteFallback: m.remotePoster)
    }
    func fanartURLs(_ m: RadarrMovie, width: Int = 1280) -> [URL?] {
        imageURLs(m.images?.image("fanart"), width: width, remoteFallback: nil)
    }

    private func imageURLs(_ image: ArrImage?, width: Int, remoteFallback: String?) -> [URL?] {
        guard let image else { return [remoteFallback.flatMap(URL.init(string:))] }
        var local = image; local.remoteUrl = nil
        var remote = image; remote.url = nil
        let urls = [client.imageURL(remote, width: width), client.imageURL(local, width: width)]
        return UserDefaults.standard.bool(forKey: Prefs.preferLocalImages) ? urls.reversed() : urls
    }
}

// MARK: - Sonarr

@Observable
final class SonarrStore {
    let client: SonarrClient
    var series: [SonarrSeries] = []
    var profiles: [ArrQualityProfile] = []
    var rootFolders: [ArrRootFolder] = []
    var tags: [ArrTag] = []
    var state: LoadState = .idle
    var lastLoaded: Date?

    let config: ServiceConfig
    var name: String { config.name }

    init(config: ServiceConfig) {
        self.config = config
        client = SonarrClient(config: config)
    }

    func load(force: Bool = false) async {
        if !force, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 30, !series.isEmpty { return }
        if series.isEmpty { state = .loading }
        do {
            async let s = client.series()
            async let p = client.qualityProfiles()
            async let r = client.rootFolders()
            async let t = client.tags()
            let (series, profiles, roots, tags) = try await (s, p, r, t)
            self.series = series
            self.profiles = profiles
            self.rootFolders = roots
            self.tags = tags
            state = .loaded
            lastLoaded = .now
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reload(seriesId: Int) async {
        guard let s = try? await client.series(id: seriesId) else { return }
        if let i = series.firstIndex(where: { $0.id == seriesId }) { series[i] = s } else { series.append(s) }
    }

    func removeLocal(seriesId: Int) { series.removeAll { $0.id == seriesId } }
    func series(id: Int) -> SonarrSeries? { series.first { $0.id == id } }
    func series(tvdbId: Int) -> SonarrSeries? { series.first { $0.tvdbId == tvdbId } }
    func profileName(_ id: Int?) -> String { profiles.first { $0.id == id }?.name ?? "—" }
    func tagNames(_ ids: [Int]?) -> [String] { (ids ?? []).compactMap { id in tags.first { $0.id == id }?.label } }

    func posterURLs(_ s: SonarrSeries, width: Int = 342) -> [URL?] {
        imageURLs(s.images?.image("poster"), width: width, remoteFallback: s.remotePoster)
    }
    func fanartURLs(_ s: SonarrSeries, width: Int = 1280) -> [URL?] {
        imageURLs(s.images?.image("fanart"), width: width, remoteFallback: nil)
    }
    private func imageURLs(_ image: ArrImage?, width: Int, remoteFallback: String?) -> [URL?] {
        guard let image else { return [remoteFallback.flatMap(URL.init(string:))] }
        var local = image; local.remoteUrl = nil
        var remote = image; remote.url = nil
        let urls = [client.imageURL(remote, width: width), client.imageURL(local, width: width)]
        return UserDefaults.standard.bool(forKey: Prefs.preferLocalImages) ? urls.reversed() : urls
    }
}

// MARK: - Seerr

@Observable
final class SeerrStore {
    let client: SeerrClient
    var me: SeerrUser?
    var counts: SeerrRequestCount?
    private var detailCache: [String: SeerrMediaDetails] = [:]
    private var detailTasks: [String: Task<SeerrMediaDetails?, Never>] = [:]

    let config: ServiceConfig
    var name: String { config.name }

    init(config: ServiceConfig) {
        self.config = config
        client = SeerrClient(config: config)
    }

    func loadBasics() async {
        async let me = try? client.me()
        async let c = try? client.requestCount()
        let (u, counts) = await (me, c)
        if let u { self.me = u }
        if let counts { self.counts = counts }
    }

    func cachedDetails(tmdbId: Int, isMovie: Bool) -> SeerrMediaDetails? {
        detailCache["\(isMovie ? "m" : "t")\(tmdbId)"]
    }

    /// Fetch details once and cache (request lists only contain IDs).
    func details(tmdbId: Int, isMovie: Bool, force: Bool = false) async -> SeerrMediaDetails? {
        let key = "\(isMovie ? "m" : "t")\(tmdbId)"
        if !force, let hit = detailCache[key] { return hit }
        if !force, let t = detailTasks[key] { return await t.value }
        let client = self.client
        let task = Task { try? await client.details(tmdbId: tmdbId, isMovie: isMovie) }
        detailTasks[key] = task
        let v = await task.value
        detailTasks[key] = nil
        if let v { detailCache[key] = v }
        return v
    }
}

// MARK: - Prowlarr

@Observable
final class ProwlarrStore {
    let client: ProwlarrClient
    var indexers: [ProwlarrIndexer] = []
    var stats: [Int: ProwlarrIndexerStat] = [:]
    var statuses: [Int: ProwlarrIndexerStatus] = [:]
    var state: LoadState = .idle

    let config: ServiceConfig
    var name: String { config.name }

    init(config: ServiceConfig) {
        self.config = config
        client = ProwlarrClient(config: config)
    }

    func load() async {
        if indexers.isEmpty { state = .loading }
        do {
            async let i = client.indexers()
            async let s = try? client.indexerStats()
            async let st = try? client.indexerStatuses()
            let (idx, stats, statuses) = try await (i, s, st)
            indexers = idx.sorted { ($0.priority ?? 25, $0.displayName) < ($1.priority ?? 25, $1.displayName) }
            self.stats = Dictionary((stats?.indexers ?? []).map { ($0.indexerId, $0) }, uniquingKeysWith: { a, _ in a })
            self.statuses = Dictionary((statuses ?? []).map { ($0.indexerId, $0) }, uniquingKeysWith: { a, _ in a })
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - qBittorrent

struct SpeedSample: Identifiable, Equatable {
    let id: Int
    let date: Date
    let down: Int
    let up: Int
}

@Observable
final class TorrentStore {
    let client: QBittorrentClient
    var torrents: [QBTorrent] = []
    var categories: [QBCategory] = []
    var tags: [String] = []
    var server = QBServerState()
    var state: LoadState = .idle
    var version: String?
    var samples: [SpeedSample] = []
    private var sampleCounter = 0

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var consumers = 0
    @ObservationIgnored private var knownIncomplete: Set<String>?
    @ObservationIgnored private var wake: CheckedContinuation<Void, Never>?

    let config: ServiceConfig
    var name: String { config.name }

    init(config: ServiceConfig) {
        self.config = config
        client = QBittorrentClient(config: config)
    }

    var downloading: [QBTorrent] { torrents.filter { $0.stateGroup == .downloading || $0.stateGroup == .stalled } }
    var activeCount: Int { torrents.filter { $0.dlspeed > 0 || $0.upspeed > 0 }.count }

    /// Views that need live data call acquire()/release() so polling speeds up only while visible.
    func acquire() {
        consumers += 1
        refreshNow()
    }
    func release() { consumers = max(0, consumers - 1) }

    func startBackground() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sync()
                let defaults = UserDefaults.standard
                let fast = max(0.5, defaults.double(forKey: Prefs.torrentInterval).nonZero ?? 1.5)
                let slow = max(3, defaults.double(forKey: Prefs.backgroundInterval).nonZero ?? 10)
                let interval = self.consumers > 0 ? fast : slow
                await self.sleep(interval)
            }
        }
    }

    @ObservationIgnored private var wakeID = 0

    private func sleep(_ seconds: Double) async {
        wakeID += 1
        let id = wakeID
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            wake = c
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.fire(id)
            }
        }
    }

    private func fire(_ id: Int? = nil) {
        if let id, id != wakeID { return }
        let c = wake
        wake = nil
        c?.resume()
    }

    func refreshNow() { fire() }

    func stop() {
        loop?.cancel()
        loop = nil
        fire()
    }

    func sync() async {
        do {
            if version == nil { version = try? await client.version() }
            let snap = try await client.sync()
            torrents = snap.torrents
            categories = snap.categories
            tags = snap.tags
            server = snap.server
            state = .loaded
            sampleCounter += 1
            samples.append(SpeedSample(id: sampleCounter, date: .now, down: snap.server.dlSpeed, up: snap.server.upSpeed))
            if samples.count > 120 { samples.removeFirst(samples.count - 120) }
            detectCompletions(snap.torrents)
        } catch {
            if torrents.isEmpty || state != .loaded { state = .failed(error.localizedDescription) }
            await client.resetSync()
        }
    }

    private func detectCompletions(_ list: [QBTorrent]) {
        let incomplete = Set(list.filter { !$0.isComplete }.map(\.hash))
        defer { knownIncomplete = incomplete }
        guard let previous = knownIncomplete, UserDefaults.standard.bool(forKey: Prefs.notifyTorrentComplete) else { return }
        for hash in previous.subtracting(incomplete) {
            if let t = list.first(where: { $0.hash == hash }), t.isComplete {
                AppModel.shared.notify(title: "Download complete", body: t.name)
            }
        }
    }

    /// Perform an action then refresh immediately.
    func perform(_ success: String? = nil, _ action: @escaping (QBittorrentClient) async throws -> Void) {
        let client = self.client
        AppModel.shared.run(success) { [weak self] in
            try await action(client)
            try? await Task.sleep(for: .milliseconds(250))
            self?.refreshNow()
        }
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
