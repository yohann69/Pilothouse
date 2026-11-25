import Foundation

/// Imports server settings from an nzb360 (Android) backup folder.
///
/// A backup contains Java-serialized maps:
///  - `com.kevinforeman.nzb360_preferences.xml` — main preferences (connection strings, API keys…)
///  - `nzb360indexers.bkp` — Newznab/Prowlarr indexers
///  - `nzb360prefs.xml`, `servers.xml` — misc
public struct NZB360Backup: Sendable {
    public var preferences: [String: JSONValue]
    public var indexers: [JSONValue]

    public init(preferences: [String: JSONValue], indexers: [JSONValue]) {
        self.preferences = preferences
        self.indexers = indexers
    }

    public enum ImportError: LocalizedError {
        case noPreferences
        public var errorDescription: String? {
            "No nzb360 preferences file was found. Select the backup folder (containing com.kevinforeman.nzb360_preferences.xml)."
        }
    }

    /// Load from a folder or from a single preferences file.
    public static func load(from url: URL) throws -> NZB360Backup {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        var prefs: [String: JSONValue] = [:]
        var indexers: [JSONValue] = []
        let files: [URL]
        if isDir.boolValue {
            files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        } else {
            files = [url]
        }
        for file in files {
            guard let data = try? Data(contentsOf: file), data.starts(with: [0xAC, 0xED]) else { continue }
            guard let objects = try? JavaDeserializer.parse(data) else { continue }
            for obj in objects {
                if let dict = obj.objectValue, dict["__class"] == nil {
                    for (k, v) in dict { prefs[k] = v }
                } else if let arr = obj.arrayValue {
                    indexers += arr
                }
            }
        }
        guard prefs.keys.contains(where: { $0.hasSuffix("_preference") }) || !indexers.isEmpty else { throw ImportError.noPreferences }
        return NZB360Backup(preferences: prefs, indexers: indexers)
    }

    private func str(_ key: String) -> String { preferences[key]?.stringValue ?? "" }
    private func bool(_ key: String) -> Bool? { preferences[key]?.boolValue }

    /// Map nzb360 preference prefixes to services.
    private static let prefixes: [(ServiceKind, String)] = [
        (.radarr, "radarr"), (.sonarr, "nzbdrone"), (.seerr, "overseerr"), (.qbittorrent, "torrent"), (.prowlarr, "prowlarr")
    ]

    /// Service configurations found in the backup.
    public func serviceConfigs() -> [ServiceConfig] {
        var out: [ServiceConfig] = []
        for (kind, prefix) in Self.prefixes {
            if kind == .qbittorrent, !str("torrent_client_preference").isEmpty,
               str("torrent_client_preference").lowercased() != "qbittorrent" { continue }
            var primary = str("\(prefix)_server_primary_connectionstring_preference")
            var apiKey = str("\(prefix)_apikey_preference")
            let local = str("\(prefix)_server_local_connectionstring_preference")
            if kind == .prowlarr, let idx = indexers.first(where: { $0["IsProwlarr"]?.boolValue == true }) {
                if apiKey.isEmpty { apiKey = idx["APIKey"]?.stringValue ?? "" }
                if primary.isEmpty { primary = idx["Host"]?.stringValue ?? "" }
            }
            guard !primary.isEmpty || !local.isEmpty else { continue }
            var cfg = ServiceConfig(kind: kind)
            cfg.enabled = bool("\(prefix)_server_enabled_preference") ?? true
            cfg.url = primary.isEmpty ? local : primary
            cfg.fallbackURL = primary.isEmpty ? "" : (local == primary ? "" : local)
            cfg.apiKey = apiKey
            if kind == .qbittorrent {
                cfg.username = firstNonEmpty(["torrent_username_preference", "torrent_server_username_preference", "torrent_user_preference"])
                cfg.password = firstNonEmpty(["torrent_password_preference", "torrent_server_password_preference", "torrent_pass_preference"])
            }
            cfg.customHeaders = parseHeaders(str("\(prefix)_customheaders_preference"))
            out.append(cfg)
        }
        return out
    }

    private func firstNonEmpty(_ keys: [String]) -> String {
        for k in keys { let v = str(k); if !v.isEmpty { return v } }
        return ""
    }

    private func parseHeaders(_ raw: String) -> [ServiceConfig.Header] {
        raw.split(whereSeparator: { $0 == "\n" || $0 == ";" }).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return ServiceConfig.Header(name: parts[0], value: parts[1])
        }
    }

    /// Sidebar order saved by nzb360 (e.g. ["Dashboard","Radarr","Seerr",…]).
    public var serviceOrder: [String] {
        guard let raw = preferences["services_order"]?.stringValue,
              let arr = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) else { return [] }
        return arr
    }
}
