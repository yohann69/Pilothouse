import Foundation

/// Shared implementation of the Servarr API surface (Radarr/Sonarr v3, Prowlarr v1).
public class ArrClient: @unchecked Sendable {
    public let http: HTTPClient
    public let apiVersion: String

    public init(config: ServiceConfig, apiVersion: String = "v3") {
        self.apiVersion = apiVersion
        self.http = HTTPClient(config: config, authHeaders: ["X-Api-Key": config.apiKey])
    }

    public var config: ServiceConfig { http.config }

    func p(_ path: String) -> String { "/api/\(apiVersion)/" + path }

    public func get<T: Decodable>(_ type: T.Type, _ path: String, query: [(String, String)] = []) async throws -> T {
        try await http.decode(T.self, .get, p(path), query: query)
    }

    public func raw(_ path: String, query: [(String, String)] = []) async throws -> JSONValue {
        try await http.decode(JSONValue.self, .get, p(path), query: query)
    }

    @discardableResult
    public func put(_ path: String, _ body: JSONValue, query: [(String, String)] = []) async throws -> JSONValue {
        let (data, _) = try await http.send(.put, p(path), query: query, body: try .encode(body))
        return data.isEmpty ? .null : ((try? JSONCoding.decoder.decode(JSONValue.self, from: data)) ?? .null)
    }

    @discardableResult
    public func post(_ path: String, _ body: JSONValue, query: [(String, String)] = []) async throws -> JSONValue {
        let (data, _) = try await http.send(.post, p(path), query: query, body: try .encode(body))
        return data.isEmpty ? .null : ((try? JSONCoding.decoder.decode(JSONValue.self, from: data)) ?? .null)
    }

    public func delete(_ path: String, query: [(String, String)] = [], body: JSONValue? = nil) async throws {
        try await http.send(.delete, p(path), query: query, body: body.map { try .encode($0) } ?? .none)
    }

    // MARK: System

    public func systemStatus() async throws -> ArrSystemStatus { try await get(ArrSystemStatus.self, "system/status") }
    public func health() async throws -> [ArrHealth] { try await get([ArrHealth].self, "health") }
    public func diskSpace() async throws -> [ArrDiskSpace] { try await get([ArrDiskSpace].self, "diskspace") }
    public func tasks() async throws -> [ArrTask] { try await get([ArrTask].self, "system/task") }
    public func tags() async throws -> [ArrTag] { try await get([ArrTag].self, "tag") }
    public func qualityProfiles() async throws -> [ArrQualityProfile] { try await get([ArrQualityProfile].self, "qualityprofile") }
    public func rootFolders() async throws -> [ArrRootFolder] { try await get([ArrRootFolder].self, "rootfolder") }

    public func createTag(_ label: String) async throws -> ArrTag {
        let v = try await post("tag", ["label": .string(label)])
        return try v.decode(ArrTag.self)
    }

    public func logs(page: Int = 1, pageSize: Int = 100, level: String? = nil) async throws -> ArrPage<ArrLogRecord> {
        var q: [(String, String)] = [("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "time"), ("sortDirection", "descending")]
        if let level, level != "all" { q.append(("level", level)) }
        return try await get(ArrPage<ArrLogRecord>.self, "log", query: q)
    }

    public func commands() async throws -> [ArrCommand] { try await get([ArrCommand].self, "command") }

    @discardableResult
    public func command(_ name: String, _ params: [String: JSONValue] = [:]) async throws -> ArrCommand {
        var body = params
        body["name"] = .string(name)
        let v = try await post("command", .object(body))
        return try v.decode(ArrCommand.self)
    }

    public func restart() async throws { try await post("system/restart", [:]) }
    public func shutdown() async throws { try await post("system/shutdown", [:]) }

    // MARK: Queue (Radarr/Sonarr)

    public func queueStatus() async throws -> ArrQueueStatus { try await get(ArrQueueStatus.self, "queue/status") }

    public func removeQueueItem(id: Int, removeFromClient: Bool = true, blocklist: Bool = false, skipRedownload: Bool = false) async throws {
        try await delete("queue/\(id)", query: [
            ("removeFromClient", "\(removeFromClient)"), ("blocklist", "\(blocklist)"), ("skipRedownload", "\(skipRedownload)")
        ])
    }

    public func grabQueueItem(id: Int) async throws { try await post("queue/grab/\(id)", [:]) }

    // MARK: Releases

    /// Push a release to the download client (interactive search "grab").
    public func grab(release: ArrRelease, extra: [String: JSONValue] = [:]) async throws {
        var body: [String: JSONValue] = ["guid": .string(release.guid), "indexerId": .number(Double(release.indexerId ?? 0))]
        for (k, v) in extra { body[k] = v }
        try await post("release", .object(body))
    }

    public func releases(query: [(String, String)]) async throws -> [ArrRelease] {
        try await get([ArrRelease].self, "release", query: query)
    }

    // MARK: Blocklist

    public func blocklist(page: Int = 1, pageSize: Int = 50) async throws -> JSONValue {
        try await raw("blocklist", query: [("page", "\(page)"), ("pageSize", "\(pageSize)"), ("sortKey", "date"), ("sortDirection", "descending")])
    }
}
