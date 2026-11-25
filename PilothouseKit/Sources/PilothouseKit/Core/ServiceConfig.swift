import Foundation

public enum ServiceKind: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case radarr, sonarr, seerr, qbittorrent, prowlarr

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .radarr: "Radarr"
        case .sonarr: "Sonarr"
        case .seerr: "Seerr"
        case .qbittorrent: "qBittorrent"
        case .prowlarr: "Prowlarr"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .radarr: 7878
        case .sonarr: 8989
        case .seerr: 5055
        case .qbittorrent: 8080
        case .prowlarr: 9696
        }
    }

    public var usesAPIKey: Bool { self != .qbittorrent }
    public var usesLogin: Bool { self == .qbittorrent }
}

/// Connection settings for a single service instance.
public struct ServiceConfig: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: ServiceKind
    public var name: String
    public var enabled: Bool
    /// Primary URL, e.g. http://192.168.1.10:7878 or https://host/radarr
    public var url: String
    /// Optional fallback URL, tried automatically when the primary is unreachable
    /// (e.g. LAN address vs. remote reverse proxy).
    public var fallbackURL: String
    public var apiKey: String
    public var username: String
    public var password: String
    /// Extra headers sent with every request (e.g. Cloudflare Access, basic auth proxies).
    public var customHeaders: [Header]
    public var allowInvalidCertificates: Bool
    public var timeout: Double

    public struct Header: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var name: String
        public var value: String
        public init(id: UUID = UUID(), name: String, value: String) {
            self.id = id; self.name = name; self.value = value
        }
    }

    public init(id: UUID = UUID(), kind: ServiceKind, name: String? = nil, enabled: Bool = true,
                url: String = "", fallbackURL: String = "", apiKey: String = "",
                username: String = "", password: String = "", customHeaders: [Header] = [],
                allowInvalidCertificates: Bool = false, timeout: Double = 20) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.displayName
        self.enabled = enabled
        self.url = url
        self.fallbackURL = fallbackURL
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.customHeaders = customHeaders
        self.allowInvalidCertificates = allowInvalidCertificates
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ServiceKind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? kind.displayName
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        fallbackURL = try c.decodeIfPresent(String.self, forKey: .fallbackURL) ?? ""
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        customHeaders = try c.decodeIfPresent([Header].self, forKey: .customHeaders) ?? []
        allowInvalidCertificates = try c.decodeIfPresent(Bool.self, forKey: .allowInvalidCertificates) ?? false
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 20
    }

    public var isConfigured: Bool {
        enabled && !url.trimmingCharacters(in: .whitespaces).isEmpty && (!kind.usesAPIKey || !apiKey.isEmpty)
    }

    /// Normalized candidate base URLs (primary first).
    public var baseURLs: [URL] {
        [url, fallbackURL].compactMap(Self.normalize)
    }

    public static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host() != nil else { return nil }
        return url
    }
}
