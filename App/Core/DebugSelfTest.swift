#if DEBUG
import SwiftUI
import PilothouseKit

/// Debug-only: PILOTHOUSE_SELFTEST=1 loads every store the UI uses and prints what each screen would show, then quits.
enum DebugSelfTest {
    @MainActor
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["PILOTHOUSE_SELFTEST"] != nil else { return }
        Task { @MainActor in
            let app = AppModel.shared
            func log(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
            log("configured: " + ServiceKind.allCases.map { "\($0.rawValue)=\(app.isConfigured($0))" }.joined(separator: " "))
            log("sidebar: " + Section.allCases.filter(app.isAvailable).map(\.title).joined(separator: ", "))
            if let r = app.radarr {
                await r.load(force: true)
                log("Movies: state=\(r.state) movies=\(r.movies.count) profiles=\(r.profiles.map(\.name)) roots=\(r.rootFolders.map(\.path)) tags=\(r.tags.count)")
                for f in MovieFilter.allCases { log("  filter \(f.rawValue): \(r.movies.filter { f.matches($0) }.count)") }
                if let m = r.movies.first { log("  poster urls: \(r.posterURLs(m).compactMap { $0?.absoluteString })") }
                if let m = r.movies.first, let u = r.posterURLs(m).compactMap({ $0 }).first {
                    let img = await ImagePipeline.shared.image(for: u, pixelWidth: 300)
                    log("  poster decode: \(img.map { "\($0.width)x\($0.height)" } ?? "FAILED")")
                }
            }
            if let s = app.sonarr {
                await s.load(force: true)
                log("Series: state=\(s.state) series=\(s.series.count) profiles=\(s.profiles.count)")
                for f in SeriesFilter.allCases { log("  filter \(f.rawValue): \(s.series.filter { f.matches($0) }.count)") }
                if let x = s.series.first, let u = s.fanartURLs(x).compactMap({ $0 }).first {
                    let img = await ImagePipeline.shared.image(for: u, pixelWidth: 1600)
                    log("  fanart decode: \(img.map { "\($0.width)x\($0.height)" } ?? "FAILED")")
                }
            }
            if let p = app.prowlarr {
                await p.load()
                log("Indexers: state=\(p.state) count=\(p.indexers.count) enabled=\(p.indexers.filter(\.enable).count) stats=\(p.stats.count)")
            }
            if let se = app.seerr {
                await se.loadBasics()
                log("Seerr: user=\(se.me?.name ?? "nil") pending=\(se.counts?.pending ?? -1) total=\(se.counts?.total ?? -1)")
                if let page = try? await se.client.requests(take: 5), let first = page.results.first, let tmdb = first.tmdbId {
                    let d = await se.details(tmdbId: tmdb, isMovie: first.isMovie)
                    log("  first request: \(d?.displayTitle ?? "nil") status=\(first.status?.label ?? "?") media=\(first.media?.status?.label ?? "?")")
                }
            }
            if let t = app.torrents {
                await t.sync()
                log("Torrents: state=\(t.state) count=\(t.torrents.count) downloading=\(t.downloading.count) categories=\(t.categories.map(\.name)) tags=\(t.tags) dl=\(t.server.dlSpeed) ul=\(t.server.upSpeed) free=\(t.server.freeSpaceOnDisk.byteString) v=\(t.version ?? "?")")
                for g in QBStateGroup.allCases { log("  group \(g.rawValue): \(t.torrents.filter { g.matches($0) }.count)") }
                if let first = t.torrents.first {
                    let files = (try? await t.client.files(first.hash))?.count ?? -1
                    let trackers = (try? await t.client.trackers(first.hash))?.count ?? -1
                    log("  inspector[\(first.name.prefix(40))]: files=\(files) trackers=\(trackers)")
                }
            }
            log("SELFTEST DONE")
            exit(0)
        }
    }
}
#endif
