import Foundation

public struct QBTorrent: Sendable, Hashable, Identifiable {
    public var hash: String
    public var name: String
    public var state: String
    public var progress: Double
    public var size: Int64
    public var totalSize: Int64
    public var dlspeed: Int
    public var upspeed: Int
    public var eta: Int
    public var ratio: Double
    public var numSeeds: Int
    public var numLeechs: Int
    public var numComplete: Int
    public var numIncomplete: Int
    public var category: String
    public var tags: [String]
    public var addedOn: Date?
    public var completionOn: Date?
    public var savePath: String
    public var contentPath: String
    public var downloaded: Int64
    public var uploaded: Int64
    public var amountLeft: Int64
    public var priority: Int
    public var seqDl: Bool
    public var firstLastPiecePrio: Bool
    public var forceStart: Bool
    public var superSeeding: Bool
    public var autoTMM: Bool
    public var dlLimit: Int
    public var upLimit: Int
    public var tracker: String
    public var magnetURI: String
    public var availability: Double
    public var ratioLimit: Double
    public var seedingTime: Int
    public var timeActive: Int
    public var lastActivity: Date?
    public var trackersCount: Int

    public var id: String { hash }

    init(hash: String, _ d: [String: JSONValue]) {
        func s(_ k: String) -> String { d[k]?.stringValue ?? "" }
        func i(_ k: String) -> Int { d[k]?.intValue ?? 0 }
        func l(_ k: String) -> Int64 { d[k]?.int64Value ?? 0 }
        func f(_ k: String) -> Double { d[k]?.doubleValue ?? 0 }
        func b(_ k: String) -> Bool { d[k]?.boolValue ?? false }
        func t(_ k: String) -> Date? {
            let v = d[k]?.doubleValue ?? 0
            return v > 0 ? Date(timeIntervalSince1970: v) : nil
        }
        self.hash = hash
        name = s("name")
        state = s("state")
        progress = f("progress")
        size = l("size")
        totalSize = l("total_size")
        dlspeed = i("dlspeed")
        upspeed = i("upspeed")
        eta = i("eta")
        ratio = f("ratio")
        numSeeds = i("num_seeds")
        numLeechs = i("num_leechs")
        numComplete = i("num_complete")
        numIncomplete = i("num_incomplete")
        category = s("category")
        tags = s("tags").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        addedOn = t("added_on")
        completionOn = t("completion_on")
        savePath = s("save_path")
        contentPath = s("content_path")
        downloaded = l("downloaded")
        uploaded = l("uploaded")
        amountLeft = l("amount_left")
        priority = i("priority")
        seqDl = b("seq_dl")
        firstLastPiecePrio = b("f_l_piece_prio")
        forceStart = b("force_start")
        superSeeding = b("super_seeding")
        autoTMM = b("auto_tmm")
        dlLimit = i("dl_limit")
        upLimit = i("up_limit")
        tracker = s("tracker")
        magnetURI = s("magnet_uri")
        availability = f("availability")
        ratioLimit = f("ratio_limit")
        seedingTime = i("seeding_time")
        timeActive = i("time_active")
        lastActivity = t("last_activity")
        trackersCount = i("trackers_count")
    }

    public var stateGroup: QBStateGroup { QBStateGroup(state: state) }
    public var isPaused: Bool { state.hasPrefix("paused") || state.hasPrefix("stopped") }
    public var isComplete: Bool { progress >= 1 }
    public var trackerHost: String { URL(string: tracker)?.host() ?? (tracker.isEmpty ? "" : tracker) }

    public var stateLabel: String {
        switch state {
        case "error": "Error"
        case "missingFiles": "Missing Files"
        case "uploading": "Seeding"
        case "pausedUP", "stoppedUP": "Completed"
        case "queuedUP": "Queued (Seed)"
        case "stalledUP": "Seeding (Stalled)"
        case "checkingUP", "checkingDL", "checkingResumeData": "Checking"
        case "forcedUP": "Forced Seeding"
        case "allocating": "Allocating"
        case "downloading": "Downloading"
        case "metaDL", "forcedMetaDL": "Fetching Metadata"
        case "pausedDL", "stoppedDL": "Paused"
        case "queuedDL": "Queued"
        case "stalledDL": "Stalled"
        case "forcedDL": "Forced Download"
        case "moving": "Moving"
        default: state.isEmpty ? "Unknown" : state
        }
    }
}

public enum QBStateGroup: String, CaseIterable, Sendable, Identifiable {
    case downloading, seeding, completed, paused, active, inactive, stalled, checking, errored, all
    public var id: String { rawValue }

    init(state: String) {
        switch state {
        case "downloading", "metaDL", "forcedDL", "forcedMetaDL", "allocating", "queuedDL": self = .downloading
        case "uploading", "forcedUP", "queuedUP": self = .seeding
        case "stalledUP": self = .seeding
        case "pausedUP", "stoppedUP": self = .completed
        case "pausedDL", "stoppedDL": self = .paused
        case "stalledDL": self = .stalled
        case "checkingUP", "checkingDL", "checkingResumeData", "moving": self = .checking
        case "error", "missingFiles", "unknown": self = .errored
        default: self = .all
        }
    }

    public var label: String {
        switch self {
        case .all: "All"
        case .downloading: "Downloading"
        case .seeding: "Seeding"
        case .completed: "Completed"
        case .paused: "Paused"
        case .active: "Active"
        case .inactive: "Inactive"
        case .stalled: "Stalled"
        case .checking: "Checking"
        case .errored: "Errored"
        }
    }

    public var symbol: String {
        switch self {
        case .all: "tray.full"
        case .downloading: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .active: "bolt.circle"
        case .inactive: "moon.circle"
        case .stalled: "exclamationmark.arrow.circlepath"
        case .checking: "arrow.triangle.2.circlepath.circle"
        case .errored: "xmark.octagon"
        }
    }

    public func matches(_ t: QBTorrent) -> Bool {
        switch self {
        case .all: true
        case .active: t.dlspeed > 0 || t.upspeed > 0
        case .inactive: t.dlspeed == 0 && t.upspeed == 0
        case .completed: t.isComplete
        case .paused: t.isPaused
        case .downloading: t.stateGroup == .downloading || (t.stateGroup == .stalled)
        default: t.stateGroup == self
        }
    }
}

public struct QBCategory: Sendable, Hashable, Identifiable {
    public var name: String
    public var savePath: String
    public var id: String { name }
}

public struct QBServerState: Sendable, Hashable {
    public var dlSpeed: Int = 0
    public var upSpeed: Int = 0
    public var dlData: Int64 = 0
    public var upData: Int64 = 0
    public var dlRateLimit: Int = 0
    public var upRateLimit: Int = 0
    public var useAltSpeedLimits: Bool = false
    public var freeSpaceOnDisk: Int64 = 0
    public var connectionStatus: String = ""
    public var dhtNodes: Int = 0
    public var allTimeDL: Int64 = 0
    public var allTimeUL: Int64 = 0
    public var globalRatio: String = ""
    public var queueing: Bool = false
    public init() {}

    mutating func merge(_ d: [String: JSONValue]) {
        if let v = d["dl_info_speed"]?.intValue { dlSpeed = v }
        if let v = d["up_info_speed"]?.intValue { upSpeed = v }
        if let v = d["dl_info_data"]?.int64Value { dlData = v }
        if let v = d["up_info_data"]?.int64Value { upData = v }
        if let v = d["dl_rate_limit"]?.intValue { dlRateLimit = v }
        if let v = d["up_rate_limit"]?.intValue { upRateLimit = v }
        if let v = d["use_alt_speed_limits"]?.boolValue { useAltSpeedLimits = v }
        if let v = d["free_space_on_disk"]?.int64Value { freeSpaceOnDisk = v }
        if let v = d["connection_status"]?.stringValue { connectionStatus = v }
        if let v = d["dht_nodes"]?.intValue { dhtNodes = v }
        if let v = d["alltime_dl"]?.int64Value { allTimeDL = v }
        if let v = d["alltime_ul"]?.int64Value { allTimeUL = v }
        if let v = d["global_ratio"]?.stringValue { globalRatio = v }
        if let v = d["queueing"]?.boolValue { queueing = v }
    }
}

/// Snapshot of the client's state after a sync.
public struct QBSnapshot: Sendable {
    public var torrents: [QBTorrent]
    public var categories: [QBCategory]
    public var tags: [String]
    public var server: QBServerState
    public var fullUpdate: Bool
}

public struct QBProperties: Codable, Sendable, Hashable {
    public var save_path: String?
    public var creation_date: Double?
    public var piece_size: Int64?
    public var comment: String?
    public var total_wasted: Int64?
    public var total_uploaded: Int64?
    public var total_downloaded: Int64?
    public var up_limit: Int?
    public var dl_limit: Int?
    public var time_elapsed: Int?
    public var seeding_time: Int?
    public var nb_connections: Int?
    public var nb_connections_limit: Int?
    public var share_ratio: Double?
    public var addition_date: Double?
    public var completion_date: Double?
    public var created_by: String?
    public var dl_speed_avg: Int?
    public var dl_speed: Int?
    public var eta: Int?
    public var last_seen: Double?
    public var peers: Int?
    public var peers_total: Int?
    public var pieces_have: Int?
    public var pieces_num: Int?
    public var reannounce: Int?
    public var seeds: Int?
    public var seeds_total: Int?
    public var total_size: Int64?
    public var up_speed_avg: Int?
    public var up_speed: Int?
    public var isPrivate: Bool?
    public var hash: String?
    public var infohash_v1: String?
    public var infohash_v2: String?
    public var download_path: String?

    enum CodingKeys: String, CodingKey {
        case save_path, creation_date, piece_size, comment, total_wasted, total_uploaded, total_downloaded, up_limit, dl_limit,
             time_elapsed, seeding_time, nb_connections, nb_connections_limit, share_ratio, addition_date, completion_date,
             created_by, dl_speed_avg, dl_speed, eta, last_seen, peers, peers_total, pieces_have, pieces_num, reannounce,
             seeds, seeds_total, total_size, up_speed_avg, up_speed, hash, infohash_v1, infohash_v2, download_path
        case isPrivate = "is_private"
    }
}

public struct QBFile: Codable, Sendable, Hashable, Identifiable {
    public var index: Int?
    public var name: String
    public var size: Int64
    public var progress: Double
    public var priority: Int
    public var is_seed: Bool?
    public var availability: Double?
    public var id: Int { index ?? name.hashValue }

    public var priorityLabel: String {
        switch priority { case 0: "Skip"; case 1: "Normal"; case 6: "High"; case 7: "Maximum"; default: "\(priority)" }
    }
}

public struct QBTracker: Codable, Sendable, Hashable, Identifiable {
    public var url: String
    public var status: Int
    public var tier: Int?
    public var num_peers: Int?
    public var num_seeds: Int?
    public var num_leeches: Int?
    public var num_downloaded: Int?
    public var msg: String?
    public var id: String { url }

    public var statusLabel: String {
        switch status { case 0: "Disabled"; case 1: "Not contacted"; case 2: "Working"; case 3: "Updating"; case 4: "Not working"; default: "\(status)" }
    }
    public var isPseudo: Bool { url.hasPrefix("** [") }

    enum CodingKeys: String, CodingKey { case url, status, tier, num_peers, num_seeds, num_leeches, num_downloaded, msg }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        status = (try? c.decode(Int.self, forKey: .status)) ?? 0
        // tier is "" for DHT/PeX pseudo trackers
        tier = try? c.decode(Int.self, forKey: .tier)
        num_peers = try? c.decode(Int.self, forKey: .num_peers)
        num_seeds = try? c.decode(Int.self, forKey: .num_seeds)
        num_leeches = try? c.decode(Int.self, forKey: .num_leeches)
        num_downloaded = try? c.decode(Int.self, forKey: .num_downloaded)
        msg = try? c.decode(String.self, forKey: .msg)
    }
}

public struct QBPeer: Sendable, Hashable, Identifiable {
    public var id: String
    public var ip: String
    public var port: Int
    public var client: String
    public var country: String
    public var countryCode: String
    public var connection: String
    public var flags: String
    public var progress: Double
    public var dlSpeed: Int
    public var upSpeed: Int
    public var downloaded: Int64
    public var uploaded: Int64
    public var relevance: Double
}

public struct QBAddOptions: Sendable {
    public var savePath: String?
    public var category: String?
    public var tags: [String] = []
    public var paused = false
    public var skipChecking = false
    public var sequential = false
    public var firstLastPiece = false
    public var rename: String?
    public var autoTMM: Bool?
    public var contentLayout: String?   // Original | Subfolder | NoSubfolder
    public var dlLimit: Int?
    public var upLimit: Int?
    public init() {}
}

public actor QBittorrentClient {
    public let http: HTTPClient
    public private(set) var apiVersion: String?
    public private(set) var appVersion: String?
    private var rid = 0
    private var torrents: [String: [String: JSONValue]] = [:]
    private var categories: [String: QBCategory] = [:]
    private var tags: Set<String> = []
    private var server = QBServerState()
    private var peerRid: [String: Int] = [:]
    private var peers: [String: [String: [String: JSONValue]]] = [:]

    public init(config: ServiceConfig) {
        http = HTTPClient(config: config, ephemeralCookies: true)
    }

    private func path(_ p: String) -> String { "/api/v2/" + p }

    public func login() async throws {
        let cfg = http.config
        let base = http.baseURL?.absoluteString ?? ""
        let (data, resp) = try await http.send(.post, path("auth/login"),
                                               body: .form([("username", cfg.username), ("password", cfg.password)]),
                                               headers: ["Referer": base, "Origin": base],
                                               acceptStatus: { _ in true })
        let body = String(decoding: data, as: UTF8.self)
        if resp.statusCode == 403 { throw APIError.loginFailed("IP banned after too many failed attempts") }
        if resp.statusCode >= 400 { throw APIError.loginFailed("HTTP \(resp.statusCode)") }
        // "Ok." on success, "Fails." on bad creds. 204 when auth is bypassed for this subnet.
        if body.contains("Fails") { throw APIError.loginFailed("Wrong username or password") }
    }

    /// Request helper that retries once after logging in when the session cookie is missing/expired.
    @discardableResult
    func call(_ p: String, form: [(String, String)]? = nil, body: RequestBody? = nil) async throws -> Data {
        try await call(.post, p, form: form, body: body)
    }

    @discardableResult
    func call(_ method: HTTPMethod, _ p: String, query: [(String, String)] = [], form: [(String, String)]? = nil,
              body: RequestBody? = nil) async throws -> Data {
        let b: RequestBody = body ?? (form.map { .form($0) } ?? .none)
        let base = http.baseURL?.absoluteString ?? ""
        do {
            return try await http.send(method, path(p), query: query, body: b, headers: ["Referer": base]).0
        } catch APIError.unauthorized {
            try await login()
            return try await http.send(method, path(p), query: query, body: b, headers: ["Referer": base]).0
        }
    }

    public func version() async throws -> String {
        let v = String(decoding: try await call(.get, "app/version"), as: UTF8.self)
        appVersion = v
        if apiVersion == nil {
            apiVersion = String(decoding: try await call(.get, "app/webapiVersion"), as: UTF8.self)
        }
        return v
    }

    /// qBittorrent ≥ 5 (WebAPI 2.11) renamed pause/resume to stop/start.
    private func usesStartStop() async -> Bool {
        if apiVersion == nil { _ = try? await version() }
        guard let v = apiVersion else { return true }
        return v.compare("2.11", options: .numeric) != .orderedAscending
    }

    // MARK: Sync

    public func resetSync() { rid = 0; torrents = [:]; categories = [:]; tags = []; server = QBServerState() }

    public func sync() async throws -> QBSnapshot {
        let data = try await call(.get, "sync/maindata", query: [("rid", "\(rid)")])
        let json = try HTTPClient.decode(JSONValue.self, from: data, path: "sync/maindata")
        guard let root = json.objectValue else { throw APIError.decoding("sync/maindata") }
        let full = root["full_update"]?.boolValue ?? false
        if full { torrents = [:]; categories = [:]; tags = []; server = QBServerState() }
        rid = root["rid"]?.intValue ?? rid

        if let t = root["torrents"]?.objectValue {
            for (hash, v) in t {
                guard let partial = v.objectValue else { continue }
                if var existing = torrents[hash] {
                    for (k, val) in partial { existing[k] = val }
                    torrents[hash] = existing
                } else {
                    torrents[hash] = partial
                }
            }
        }
        for h in root["torrents_removed"]?.arrayValue ?? [] { if let s = h.stringValue { torrents[s] = nil } }
        if let c = root["categories"]?.objectValue {
            for (name, v) in c {
                let sp = v["savePath"]?.stringValue ?? categories[name]?.savePath ?? ""
                categories[name] = QBCategory(name: name, savePath: sp)
            }
        }
        for c in root["categories_removed"]?.arrayValue ?? [] { if let s = c.stringValue { categories[s] = nil } }
        for t in root["tags"]?.arrayValue ?? [] { if let s = t.stringValue { tags.insert(s) } }
        for t in root["tags_removed"]?.arrayValue ?? [] { if let s = t.stringValue { tags.remove(s) } }
        if let s = root["server_state"]?.objectValue { server.merge(s) }

        return QBSnapshot(
            torrents: torrents.map { QBTorrent(hash: $0.key, $0.value) },
            categories: categories.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            tags: tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            server: server,
            fullUpdate: full
        )
    }

    // MARK: Torrent actions

    private func hashes(_ h: [String]) -> String { h.isEmpty ? "all" : h.joined(separator: "|") }

    public func pause(_ h: [String]) async throws {
        try await call("torrents/\(await usesStartStop() ? "stop" : "pause")", form: [("hashes", hashes(h))])
    }
    public func resume(_ h: [String]) async throws {
        try await call("torrents/\(await usesStartStop() ? "start" : "resume")", form: [("hashes", hashes(h))])
    }
    public func delete(_ h: [String], deleteFiles: Bool) async throws {
        try await call("torrents/delete", form: [("hashes", hashes(h)), ("deleteFiles", "\(deleteFiles)")])
    }
    public func recheck(_ h: [String]) async throws { try await call("torrents/recheck", form: [("hashes", hashes(h))]) }
    public func reannounce(_ h: [String]) async throws { try await call("torrents/reannounce", form: [("hashes", hashes(h))]) }
    public func setForceStart(_ h: [String], _ value: Bool) async throws {
        try await call("torrents/setForceStart", form: [("hashes", hashes(h)), ("value", "\(value)")])
    }
    public func setSuperSeeding(_ h: [String], _ value: Bool) async throws {
        try await call("torrents/setSuperSeeding", form: [("hashes", hashes(h)), ("value", "\(value)")])
    }
    public func setAutoManagement(_ h: [String], _ value: Bool) async throws {
        try await call("torrents/setAutoManagement", form: [("hashes", hashes(h)), ("enable", "\(value)")])
    }
    public enum QueueMove: String, Sendable { case top = "topPrio", bottom = "bottomPrio", up = "increasePrio", down = "decreasePrio" }
    public func move(_ h: [String], _ m: QueueMove) async throws { try await call("torrents/\(m.rawValue)", form: [("hashes", hashes(h))]) }
    public func setCategory(_ h: [String], _ category: String) async throws {
        try await call("torrents/setCategory", form: [("hashes", hashes(h)), ("category", category)])
    }
    public func addTags(_ h: [String], _ tags: [String]) async throws {
        try await call("torrents/addTags", form: [("hashes", hashes(h)), ("tags", tags.joined(separator: ","))])
    }
    public func removeTags(_ h: [String], _ tags: [String]) async throws {
        try await call("torrents/removeTags", form: [("hashes", hashes(h)), ("tags", tags.joined(separator: ","))])
    }
    public func setLocation(_ h: [String], _ location: String) async throws {
        try await call("torrents/setLocation", form: [("hashes", hashes(h)), ("location", location)])
    }
    public func rename(_ hash: String, _ name: String) async throws {
        try await call("torrents/rename", form: [("hash", hash), ("name", name)])
    }
    public func toggleSequential(_ h: [String]) async throws { try await call("torrents/toggleSequentialDownload", form: [("hashes", hashes(h))]) }
    public func toggleFirstLast(_ h: [String]) async throws { try await call("torrents/toggleFirstLastPiecePrio", form: [("hashes", hashes(h))]) }
    /// Bytes per second; 0 = unlimited.
    public func setDownloadLimit(_ h: [String], _ limit: Int) async throws {
        try await call("torrents/setDownloadLimit", form: [("hashes", hashes(h)), ("limit", "\(limit)")])
    }
    public func setUploadLimit(_ h: [String], _ limit: Int) async throws {
        try await call("torrents/setUploadLimit", form: [("hashes", hashes(h)), ("limit", "\(limit)")])
    }
    /// ratio: -2 global, -1 unlimited. minutes: -2 global, -1 unlimited.
    public func setShareLimits(_ h: [String], ratio: Double, seedingMinutes: Int, inactiveMinutes: Int = -2) async throws {
        try await call("torrents/setShareLimits", form: [
            ("hashes", hashes(h)), ("ratioLimit", "\(ratio)"), ("seedingTimeLimit", "\(seedingMinutes)"),
            ("inactiveSeedingTimeLimit", "\(inactiveMinutes)")
        ])
    }

    // MARK: Details

    public func properties(_ hash: String) async throws -> QBProperties {
        try HTTPClient.decode(QBProperties.self, from: try await call(.get, "torrents/properties", query: [("hash", hash)]), path: "properties")
    }
    public func files(_ hash: String) async throws -> [QBFile] {
        let files = try HTTPClient.decode([QBFile].self, from: try await call(.get, "torrents/files", query: [("hash", hash)]), path: "files")
        return files.enumerated().map { i, f in var f = f; if f.index == nil { f.index = i }; return f }
    }
    public func trackers(_ hash: String) async throws -> [QBTracker] {
        try HTTPClient.decode([QBTracker].self, from: try await call(.get, "torrents/trackers", query: [("hash", hash)]), path: "trackers")
    }
    public func setFilePriority(_ hash: String, ids: [Int], priority: Int) async throws {
        try await call("torrents/filePrio", form: [("hash", hash), ("id", ids.map(String.init).joined(separator: "|")), ("priority", "\(priority)")])
    }
    public func renameFile(_ hash: String, oldPath: String, newPath: String) async throws {
        try await call("torrents/renameFile", form: [("hash", hash), ("oldPath", oldPath), ("newPath", newPath)])
    }
    public func addTrackers(_ hash: String, urls: [String]) async throws {
        try await call("torrents/addTrackers", form: [("hash", hash), ("urls", urls.joined(separator: "\n"))])
    }
    public func removeTrackers(_ hash: String, urls: [String]) async throws {
        try await call("torrents/removeTrackers", form: [("hash", hash), ("urls", urls.joined(separator: "|"))])
    }

    public func renameFolder(_ hash: String, oldPath: String, newPath: String) async throws {
        try await call("torrents/renameFolder", form: [("hash", hash), ("oldPath", oldPath), ("newPath", newPath)])
    }

    public func editTracker(_ hash: String, from old: String, to new: String) async throws {
        try await call("torrents/editTracker", form: [("hash", hash), ("url", old), ("origUrl", old), ("newUrl", new)])
    }

    /// HTTP web seeds of a torrent.
    public func webSeeds(_ hash: String) async throws -> [String] {
        let data = try await call(.get, "torrents/webseeds", query: [("hash", hash)])
        let list = try HTTPClient.decode([JSONValue].self, from: data, path: "webseeds")
        return list.compactMap { $0["url"]?.stringValue }
    }
    public func addWebSeeds(_ hash: String, urls: [String]) async throws {
        try await call("torrents/addWebSeeds", form: [("hash", hash), ("urls", urls.joined(separator: "|"))])
    }
    public func removeWebSeeds(_ hash: String, urls: [String]) async throws {
        try await call("torrents/removeWebSeeds", form: [("hash", hash), ("urls", urls.joined(separator: "|"))])
    }

    /// Peers as "ip:port".
    public func addPeers(_ hashes: [String], peers: [String]) async throws {
        try await call("torrents/addPeers", form: [("hashes", hashes.joined(separator: "|")), ("peers", peers.joined(separator: "|"))])
    }
    public func banPeers(_ peers: [String]) async throws {
        try await call("transfer/banPeers", form: [("peers", peers.joined(separator: "|"))])
    }

    /// The .torrent file of a torrent.
    public func exportTorrent(_ hash: String) async throws -> Data {
        try await call(.get, "torrents/export", query: [("hash", hash)])
    }

    public func setDownloadPath(_ h: [String], _ path: String) async throws {
        try await call("torrents/setDownloadPath", form: [("id", hashes(h)), ("path", path)])
    }

    public func peers(_ hash: String) async throws -> [QBPeer] {
        let r = peerRid[hash] ?? 0
        let data = try await call(.get, "sync/torrentPeers", query: [("hash", hash), ("rid", "\(r)")])
        let json = try HTTPClient.decode(JSONValue.self, from: data, path: "torrentPeers")
        var current = (json["full_update"]?.boolValue ?? false) ? [:] : (peers[hash] ?? [:])
        if let p = json["peers"]?.objectValue {
            for (k, v) in p {
                guard let partial = v.objectValue else { continue }
                var e = current[k] ?? [:]
                for (kk, vv) in partial { e[kk] = vv }
                current[k] = e
            }
        }
        for k in json["peers_removed"]?.arrayValue ?? [] { if let s = k.stringValue { current[s] = nil } }
        peers[hash] = current
        peerRid[hash] = json["rid"]?.intValue ?? r
        return current.map { key, d in
            QBPeer(id: key, ip: d["ip"]?.stringValue ?? key, port: d["port"]?.intValue ?? 0,
                   client: d["client"]?.stringValue ?? "", country: d["country"]?.stringValue ?? "",
                   countryCode: d["country_code"]?.stringValue ?? "", connection: d["connection"]?.stringValue ?? "",
                   flags: d["flags"]?.stringValue ?? "", progress: d["progress"]?.doubleValue ?? 0,
                   dlSpeed: d["dl_speed"]?.intValue ?? 0, upSpeed: d["up_speed"]?.intValue ?? 0,
                   downloaded: d["downloaded"]?.int64Value ?? 0, uploaded: d["uploaded"]?.int64Value ?? 0,
                   relevance: d["relevance"]?.doubleValue ?? 0)
        }.sorted { $0.dlSpeed + $0.upSpeed > $1.dlSpeed + $1.upSpeed }
    }

    public func clearPeers(_ hash: String) { peers[hash] = nil; peerRid[hash] = nil }

    // MARK: Adding

    public func add(urls: [String], torrentFiles: [(name: String, data: Data)] = [], options: QBAddOptions) async throws {
        let boundary = "pilothouse-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        if !urls.isEmpty { field("urls", urls.joined(separator: "\n")) }
        for f in torrentFiles {
            let safe = f.name.replacingOccurrences(of: "\"", with: "'")
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"torrents\"; filename=\"\(safe)\"\r\nContent-Type: application/x-bittorrent\r\n\r\n".utf8))
            body.append(f.data)
            body.append(Data("\r\n".utf8))
        }
        if let v = options.savePath, !v.isEmpty { field("savepath", v) }
        if let v = options.category, !v.isEmpty { field("category", v) }
        if !options.tags.isEmpty { field("tags", options.tags.joined(separator: ",")) }
        let startStop = await usesStartStop()
        field(startStop ? "stopped" : "paused", "\(options.paused)")
        field("skip_checking", "\(options.skipChecking)")
        field("sequentialDownload", "\(options.sequential)")
        field("firstLastPiecePrio", "\(options.firstLastPiece)")
        if let v = options.rename, !v.isEmpty { field("rename", v) }
        if let v = options.autoTMM { field("autoTMM", "\(v)") }
        if let v = options.contentLayout { field("contentLayout", v) }
        if let v = options.dlLimit, v > 0 { field("dlLimit", "\(v)") }
        if let v = options.upLimit, v > 0 { field("upLimit", "\(v)") }
        body.append(Data("--\(boundary)--\r\n".utf8))
        let data = try await call("torrents/add", body: .multipart(boundary: boundary, data: body))
        if String(decoding: data, as: UTF8.self).contains("Fails") {
            throw APIError.http(status: 200, message: "qBittorrent rejected the torrent (invalid or duplicate).")
        }
    }

    // MARK: Categories / tags

    public func createCategory(_ name: String, savePath: String) async throws {
        try await call("torrents/createCategory", form: [("category", name), ("savePath", savePath)])
    }
    public func editCategory(_ name: String, savePath: String) async throws {
        try await call("torrents/editCategory", form: [("category", name), ("savePath", savePath)])
    }
    public func removeCategories(_ names: [String]) async throws {
        try await call("torrents/removeCategories", form: [("categories", names.joined(separator: "\n"))])
    }
    public func createTags(_ names: [String]) async throws {
        try await call("torrents/createTags", form: [("tags", names.joined(separator: ","))])
    }
    public func deleteTags(_ names: [String]) async throws {
        try await call("torrents/deleteTags", form: [("tags", names.joined(separator: ","))])
    }

    // MARK: Transfer / app

    public func toggleAltSpeed() async throws { try await call("transfer/toggleSpeedLimitsMode") }
    public func altSpeedEnabled() async throws -> Bool {
        String(decoding: try await call(.get, "transfer/speedLimitsMode"), as: UTF8.self).trimmingCharacters(in: .whitespaces) == "1"
    }
    public func setGlobalDownloadLimit(_ bytes: Int) async throws { try await call("transfer/setDownloadLimit", form: [("limit", "\(bytes)")]) }
    public func setGlobalUploadLimit(_ bytes: Int) async throws { try await call("transfer/setUploadLimit", form: [("limit", "\(bytes)")]) }

    public func preferences() async throws -> JSONValue {
        try HTTPClient.decode(JSONValue.self, from: try await call(.get, "app/preferences"), path: "preferences")
    }
    public func setPreferences(_ prefs: [String: JSONValue]) async throws {
        let json = String(decoding: try JSONCoding.encoder.encode(JSONValue.object(prefs)), as: UTF8.self)
        try await call("app/setPreferences", form: [("json", json)])
    }
    public func defaultSavePath() async throws -> String {
        String(decoding: try await call(.get, "app/defaultSavePath"), as: UTF8.self)
    }
    public func log(lastId: Int = -1) async throws -> [JSONValue] {
        try HTTPClient.decode([JSONValue].self, from: try await call(.get, "log/main", query: [("last_known_id", "\(lastId)")]), path: "log")
    }
}
