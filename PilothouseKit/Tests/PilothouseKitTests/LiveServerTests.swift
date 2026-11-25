import Foundation
import Testing
@testable import PilothouseKit

/// Integration tests that run against the real home server described by the nzb360 backup.
/// Set PILOTHOUSE_BACKUP to an nzb360 backup folder; without one these suites are skipped.
/// Write tests are reversible: every change is restored.
enum Live {
    static let backupURL: URL = {
        if let p = ProcessInfo.processInfo.environment["PILOTHOUSE_BACKUP"] { return URL(fileURLWithPath: p) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // PilothouseKitTests
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.lastPathComponent.hasPrefix("nzb360_backup") } ?? root
    }()

    static let configs: [ServiceKind: ServiceConfig] = {
        guard let backup = try? NZB360Backup.load(from: backupURL) else { return [:] }
        var out: [ServiceKind: ServiceConfig] = [:]
        for c in backup.serviceConfigs() { out[c.kind] = c }
        // The backup's Prowlarr host is stale; it now lives on the same box as the others.
        if var p = out[.prowlarr], let radarrHost = out[.radarr].flatMap({ URL(string: $0.url)?.host() }) {
            if let override = ProcessInfo.processInfo.environment["PILOTHOUSE_PROWLARR_URL"] { p.url = override }
            else { p.fallbackURL = "http://\(radarrHost):9696" }
            out[.prowlarr] = p
        }
        return out
    }()

    /// Live suites only run when a backup with all five services is available.
    static var available: Bool { configs.count == ServiceKind.allCases.count }

    static var radarr: RadarrClient { RadarrClient(config: configs[.radarr]!) }
    static var sonarr: SonarrClient { SonarrClient(config: configs[.sonarr]!) }
    static var prowlarr: ProwlarrClient { ProwlarrClient(config: configs[.prowlarr]!) }
    static var seerr: SeerrClient { SeerrClient(config: configs[.seerr]!) }
    static var qbit: QBittorrentClient { QBittorrentClient(config: configs[.qbittorrent]!) }
}

@Suite("Backup import")
struct BackupTests {
    @Test(.enabled(if: Live.available)) func importsAllServices() throws {
        let backup = try NZB360Backup.load(from: Live.backupURL)
        let kinds = Set(backup.serviceConfigs().map(\.kind))
        #expect(kinds == Set(ServiceKind.allCases))
        let radarr = try #require(backup.serviceConfigs().first { $0.kind == .radarr })
        #expect(radarr.url.hasPrefix("http://"))
        #expect(radarr.apiKey.count == 32)
        #expect(backup.serviceOrder.first == "Dashboard")
        #expect(backup.indexers.count == 1)
    }

    @Test func jsonDates() {
        #expect(JSONCoding.parseDate("2026-09-27T09:07:38Z") != nil)
        #expect(JSONCoding.parseDate("2026-11-24T17:57:01.000Z") != nil)
        #expect(JSONCoding.parseDate("2026-11-24T17:57:01.1234567Z") != nil)
        #expect(JSONCoding.parseDate("2026-11-24") != nil)
    }

    @Test func queryEncodingIsStrict() throws {
        let url = try HTTPClient.build(base: URL(string: "http://h:1/base")!, path: "/api/v1/search", query: [("query", "Don't (2024)! & co")])
        #expect(url.absoluteString == "http://h:1/base/api/v1/search?query=Don%27t%20%282024%29%21%20%26%20co")
    }
}

@Suite("Radarr live", .serialized, .enabled(if: Live.available))
struct RadarrLiveTests {
    let c = Live.radarr

    @Test func system() async throws {
        let s = try await c.systemStatus()
        #expect(s.appName == "Radarr")
        _ = try await c.health()
        #expect(try await !c.diskSpace().isEmpty)
        #expect(try await !c.qualityProfiles().isEmpty)
        #expect(try await !c.rootFolders().isEmpty)
        _ = try await c.tags()
        #expect(try await !c.tasks().isEmpty)
        let logs = try await c.logs(pageSize: 20)
        #expect(logs.records.count <= 20)
        _ = try await c.commands()
        _ = try await c.queueStatus()
        _ = try await c.blocklist()
    }

    @Test func library() async throws {
        let movies = try await c.movies()
        #expect(!movies.isEmpty)
        let m = try #require(movies.first { $0.downloaded } ?? movies.first)
        let id = try #require(m.id)
        let one = try await c.movie(id: id)
        #expect(one.tmdbId == m.tmdbId)
        _ = try await c.movieFiles(movieId: id)
        _ = try await c.history(movieId: id)
        #expect(c.imageURL(m.images?.image("poster"), width: 300) != nil)
    }

    @Test func activity() async throws {
        let q = try await c.queue()
        #expect(q.totalRecords >= q.records.count)
        let h = try await c.history(pageSize: 30)
        #expect(h.records.count <= 30)
        let cal = try await c.calendar(start: .now.addingTimeInterval(-86400 * 30), end: .now.addingTimeInterval(86400 * 90))
        _ = cal
        _ = try await c.wantedMissing()
        _ = try await c.wantedCutoff()
    }

    @Test func lookup() async throws {
        let r = try await c.lookup(term: "Inception")
        #expect(r.contains { $0.tmdbId == 27205 })
        let raw = try await c.lookup(tmdbId: 27205)
        #expect(raw["title"]?.stringValue == "Inception")
    }

    @Test func interactiveSearch() async throws {
        let movies = try await c.movies()
        let m = try #require(movies.first)
        let releases = try await c.releases(movieId: m.id!)
        print("Radarr releases for \(m.title): \(releases.count)")
    }

    @Test func editRoundTrip() async throws {
        let movies = try await c.movies()
        let m = try #require(movies.first)
        let id = m.id!
        let original = m.monitored ?? true
        let toggled = try await c.update(movieId: id) { $0["monitored"] = .bool(!original) }
        #expect(toggled.monitored == !original)
        try await c.setMonitored(movieIds: [id], monitored: original)
        #expect(try await c.movie(id: id).monitored == original)
    }

    @Test func tagRoundTrip() async throws {
        let tag = try await c.createTag("pilothouse-test")
        #expect(tag.label == "pilothouse-test")
        try await c.delete("tag/\(tag.id)")
        #expect(try await !c.tags().contains { $0.id == tag.id })
    }

    @Test func addAndDeleteMovie() async throws {
        let tmdb = 653 // Nosferatu (1922)
        let library = try await c.movies()
        try #require(!library.contains { $0.tmdbId == tmdb }, "Test movie already in library")
        let lookup = try await c.lookup(tmdbId: tmdb)
        let profile = try #require(try await c.qualityProfiles().first)
        let root = try #require(try await c.rootFolders().first)
        let added = try await c.add(lookup: lookup, qualityProfileId: profile.id, rootFolderPath: root.path,
                                    monitored: false, minimumAvailability: "released", tags: [], searchForMovie: false)
        let id = try #require(added.id)
        #expect(added.tmdbId == tmdb)
        try await c.deleteMovie(id: id, deleteFiles: false, addExclusion: false)
        #expect(try await !c.movies().contains { $0.tmdbId == tmdb })
    }
}

@Suite("Sonarr live", .serialized, .enabled(if: Live.available))
struct SonarrLiveTests {
    let c = Live.sonarr

    @Test func system() async throws {
        #expect(try await c.systemStatus().appName == "Sonarr")
        _ = try await c.health()
        _ = try await c.diskSpace()
        #expect(try await !c.qualityProfiles().isEmpty)
        #expect(try await !c.rootFolders().isEmpty)
        _ = try await c.tasks()
        _ = try await c.logs(pageSize: 10)
    }

    @Test func library() async throws {
        let series = try await c.series()
        #expect(!series.isEmpty)
        let s = try #require(series.first { ($0.statistics?.episodeFileCount ?? 0) > 0 } ?? series.first)
        let id = s.id!
        _ = try await c.series(id: id)
        let eps = try await c.episodes(seriesId: id)
        #expect(!eps.isEmpty)
        _ = try await c.episodeFiles(seriesId: id)
        _ = try await c.history(seriesId: id)
        if let e = eps.first {
            _ = try await c.episode(id: e.id)
            _ = try await c.history(episodeId: e.id)
        }
    }

    @Test func activity() async throws {
        _ = try await c.queue()
        _ = try await c.history(pageSize: 30)
        _ = try await c.calendar(start: .now.addingTimeInterval(-86400 * 7), end: .now.addingTimeInterval(86400 * 30))
        _ = try await c.wantedMissing()
        _ = try await c.wantedCutoff()
    }

    @Test func lookup() async throws {
        let r = try await c.lookup(term: "Breaking Bad")
        #expect(r.contains { $0.tvdbId == 81189 })
    }

    @Test func interactiveSearch() async throws {
        let series = try await c.series()
        let s = try #require(series.first)
        let eps = try await c.episodes(seriesId: s.id!)
        let e = try #require(eps.first { $0.seasonNumber > 0 })
        let releases = try await c.releases(episodeId: e.id)
        print("Sonarr releases for \(s.title) \(e.code): \(releases.count)")
    }

    @Test func monitorRoundTrips() async throws {
        let series = try await c.series()
        let s = try #require(series.first { ($0.seasons ?? []).contains { $0.seasonNumber > 0 } })
        let id = s.id!
        let season = try #require(s.seasons?.first { $0.seasonNumber > 0 })
        // Season monitoring
        try await c.setSeasonMonitored(seriesId: id, seasonNumber: season.seasonNumber, monitored: !season.monitored)
        #expect(try await c.series(id: id).seasons?.first { $0.seasonNumber == season.seasonNumber }?.monitored == !season.monitored)
        try await c.setSeasonMonitored(seriesId: id, seasonNumber: season.seasonNumber, monitored: season.monitored)
        #expect(try await c.series(id: id).seasons?.first { $0.seasonNumber == season.seasonNumber }?.monitored == season.monitored)
        // Episode monitoring
        let eps = try await c.episodes(seriesId: id, seasonNumber: season.seasonNumber)
        let e = try #require(eps.first)
        try await c.setEpisodesMonitored(ids: [e.id], monitored: !e.monitored)
        #expect(try await c.episode(id: e.id).monitored == !e.monitored)
        try await c.setEpisodesMonitored(ids: [e.id], monitored: e.monitored)
        #expect(try await c.episode(id: e.id).monitored == e.monitored)
    }

    @Test func addAndDeleteSeries() async throws {
        let tvdb = 76156 // Fawlty Towers
        let library = try await c.series()
        try #require(!library.contains { $0.tvdbId == tvdb }, "Test series already in library")
        let lookup = try #require(try await c.rawLookup(term: "tvdb:\(tvdb)").first)
        let profile = try #require(try await c.qualityProfiles().first)
        let root = try #require(try await c.rootFolders().first)
        let added = try await c.add(lookup: lookup, qualityProfileId: profile.id, rootFolderPath: root.path, monitor: .none,
                                    seriesType: "standard", seasonFolder: true, tags: [], searchForMissing: false)
        let id = try #require(added.id)
        try await c.deleteSeries(id: id, deleteFiles: false, addExclusion: false)
        #expect(try await !c.series().contains { $0.tvdbId == tvdb })
    }
}

@Suite("Prowlarr live", .serialized, .enabled(if: Live.available))
struct ProwlarrLiveTests {
    let c = Live.prowlarr

    @Test func everything() async throws {
        #expect(try await c.systemStatus().appName == "Prowlarr")
        let idx = try await c.indexers()
        #expect(!idx.isEmpty)
        _ = try await c.indexerStats()
        _ = try await c.indexerStatuses()
        _ = try await c.applications()
        _ = try await c.downloadClients()
        _ = try await c.history(pageSize: 10)
        _ = try await c.health()
        let results = try await c.search(query: "ubuntu", limit: 20)
        print("Prowlarr results: \(results.count)")
        let movies = try await c.search(query: "Inception", type: .movie, categories: [2000], limit: 20)
        print("Prowlarr movie results: \(movies.count)")
        if let first = idx.first(where: \.enable) { try await c.testIndexer(id: first.id) }
    }
}

@Suite("Seerr live", .serialized, .enabled(if: Live.available))
struct SeerrLiveTests {
    let c = Live.seerr

    @Test func everything() async throws {
        _ = try await c.status()
        let me = try await c.me()
        print("Seerr user: \(me.name) manage=\(me.canManageRequests)")
        for cat in SeerrDiscoverCategory.allCases {
            let page = try await c.discover(cat)
            #expect(!page.results.isEmpty, "\(cat)")
        }
        let s = try await c.search("Don't Look Up!")
        #expect(!s.results.isEmpty)
        let movie = try await c.movie(tmdbId: 27205)
        #expect(movie.displayTitle == "Inception")
        let tv = try await c.tv(tmdbId: 1396)
        #expect(!(tv.seasons ?? []).isEmpty)
        _ = try await c.recommendations(tmdbId: 27205, isMovie: true)
        for f in SeerrRequestFilter.allCases { _ = try await c.requests(filter: f, take: 10) }
        _ = try await c.requestCount()
        let radarrs = try await c.radarrServers()
        if let r = radarrs.first { #expect(try await !c.serviceDetails(isMovie: true, serverId: r.id).profiles.isEmpty) }
        let sonarrs = try await c.sonarrServers()
        if let s = sonarrs.first { _ = try await c.serviceDetails(isMovie: false, serverId: s.id) }
        _ = try await c.issues(filter: "all")
    }
}

@Suite("qBittorrent live", .serialized, .enabled(if: Live.available))
struct QBittorrentLiveTests {
    @Test func readAndSync() async throws {
        let c = Live.qbit
        let v = try await c.version()
        print("qBittorrent \(v) api \(await c.apiVersion ?? "?")")
        let first = try await c.sync()
        #expect(first.fullUpdate)
        let second = try await c.sync()
        #expect(second.torrents.count == first.torrents.count)
        #expect(!second.fullUpdate)
        _ = try await c.preferences()
        _ = try await c.defaultSavePath()
        _ = try await c.altSpeedEnabled()
        _ = try await c.log()
        if let t = first.torrents.first {
            _ = try await c.properties(t.hash)
            #expect(try await !c.files(t.hash).isEmpty)
            _ = try await c.trackers(t.hash)
            _ = try await c.peers(t.hash)
            _ = try await c.peers(t.hash)
        }
    }

    @Test func altSpeedRoundTrip() async throws {
        let c = Live.qbit
        let before = try await c.altSpeedEnabled()
        try await c.toggleAltSpeed()
        #expect(try await c.altSpeedEnabled() == !before)
        try await c.toggleAltSpeed()
        #expect(try await c.altSpeedEnabled() == before)
    }

    @Test func addCategorizeTagDelete() async throws {
        let c = Live.qbit
        let hash = "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c" // Big Buck Bunny (public domain)
        let magnet = "magnet:?xt=urn:btih:\(hash)&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337"
        var snap = try await c.sync()
        try #require(!snap.torrents.contains { $0.hash == hash }, "test torrent already present")
        var opts = QBAddOptions()
        opts.paused = true
        try await c.add(urls: [magnet], options: opts)
        var found: QBTorrent?
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(300))
            snap = try await c.sync()
            if let t = snap.torrents.first(where: { $0.hash == hash }) { found = t; break }
        }
        func cleanup() async {
            try? await c.delete([hash], deleteFiles: true)
            try? await c.removeCategories(["pilothouse-test"])
            try? await c.deleteTags(["pilothouse-tag"])
        }
        do {
            let t = try #require(found, "torrent did not appear")
            #expect(t.isPaused)
            try await c.createCategory("pilothouse-test", savePath: "")
            try await c.setCategory([hash], "pilothouse-test")
            try await c.addTags([hash], ["pilothouse-tag"])
            try await c.setDownloadLimit([hash], 1024 * 100)
            if snap.server.queueing { try await c.move([hash], .top) }
            try await c.rename(hash, "pilothouse rename test")
            try await Task.sleep(for: .milliseconds(600))
            snap = try await c.sync()
            let t2 = try #require(snap.torrents.first { $0.hash == hash })
            #expect(t2.category == "pilothouse-test")
            #expect(t2.tags.contains("pilothouse-tag"))
            #expect(t2.dlLimit == 1024 * 100)
            #expect(t2.name == "pilothouse rename test")
            // Trackers: add, edit, remove
            let tr1 = "udp://tracker.example.invalid:1337/announce", tr2 = "udp://tracker2.example.invalid:1337/announce"
            try await c.addTrackers(hash, urls: [tr1])
            try await c.editTracker(hash, from: tr1, to: tr2)
            #expect(try await c.trackers(hash).contains { $0.url == tr2 })
            try await c.removeTrackers(hash, urls: [tr2])
            #expect(try await !c.trackers(hash).contains { $0.url == tr2 })
            // Web seeds and peers endpoints
            _ = try await c.webSeeds(hash)
            try await c.addPeers([hash], peers: ["127.0.0.1:6881"])
            // Export .torrent (metadata may not be fetched yet for a fresh magnet)
            if let data = try? await c.exportTorrent(hash) { #expect(data.isEmpty || data.first == UInt8(ascii: "d")) }
            // Preferences write path with an unchanged value
            let prefs = try await c.preferences()
            if let lan = prefs["limit_lan_peers"] { try await c.setPreferences(["limit_lan_peers": lan]) }
            try await c.resume([hash])
            try await c.pause([hash])
        } catch {
            await cleanup()
            throw error
        }
        await cleanup()
        try await Task.sleep(for: .milliseconds(600))
        snap = try await c.sync()
        #expect(!snap.torrents.contains { $0.hash == hash })
        #expect(!snap.categories.contains { $0.name == "pilothouse-test" })
    }
}

@Suite("Network discovery", .serialized, .enabled(if: Live.available))
struct DiscoveryLiveTests {
    @Test func fingerprintsKnownServer() async throws {
        let host = try #require(Live.configs[.radarr].flatMap { URL(string: $0.url)?.host() })
        for kind in ServiceKind.allCases {
            let port = NetworkScanner.ports(for: kind)[0]
            let found = await NetworkScanner.fingerprint(host: host, port: port)
            #expect(found.first?.kind == kind, "\(kind) on \(port)")
            if kind == .radarr || kind == .sonarr || kind == .prowlarr {
                #expect(found.first?.apiKey == Live.configs[kind]?.apiKey, "api key for \(kind)")
            }
        }
        #expect(await NetworkScanner.isOpen(host: host, port: 7878, timeout: 1))
        #expect(await !NetworkScanner.isOpen(host: host, port: 1, timeout: 1))
    }

    @Test func fullSubnetScan() async throws {
        #expect(!NetworkScanner.localSubnetPrefixes().isEmpty)
        let start = Date()
        var found: [DiscoveredService] = []
        for await s in NetworkScanner.scan() { found.append(s) }
        let elapsed = Date().timeIntervalSince(start)
        print("Discovery: \(found.count) services in \(String(format: "%.1f", elapsed))s:", found.map { "\($0.kind.rawValue)@\($0.url) key=\($0.apiKey != nil)" })
        #expect(Set(found.map(\.kind)) == Set(ServiceKind.allCases))
        #expect(elapsed < 60)
    }
}
