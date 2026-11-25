import Foundation
import Network

/// A service found on the network.
public struct DiscoveredService: Sendable, Hashable, Identifiable {
    public var kind: ServiceKind
    public var url: String
    public var title: String
    public var version: String?
    /// Filled in when the service exposes it (Servarr apps with auth disabled for local addresses).
    public var apiKey: String?
    /// qBittorrent requires a username/password.
    public var needsLogin: Bool
    public var id: String { kind.rawValue + "|" + url }
}

/// Finds Radarr, Sonarr, Prowlarr, Seerr and qBittorrent on the local network:
/// a fast TCP probe over likely hosts and ports, then an HTTP fingerprint of each open port.
public enum NetworkScanner {
    /// Ports each service commonly listens on (defaults first).
    public static func ports(for kind: ServiceKind) -> [Int] {
        switch kind {
        case .radarr: [7878, 7879]
        case .sonarr: [8989, 8990]
        case .prowlarr: [9696, 9697]
        case .seerr: [5055, 5056]
        case .qbittorrent: [8080, 8081, 8090, 8085, 9080, 8888]
        }
    }

    /// Hosts to scan: localhost, hosts already in use, and every address of the Mac's private /24 networks.
    public static func candidateHosts(extra: [String] = []) -> [String] {
        var hosts: [String] = []
        func add(_ h: String) { if !h.isEmpty, !hosts.contains(h) { hosts.append(h) } }
        add("127.0.0.1")
        extra.forEach(add)
        for prefix in localSubnetPrefixes() {
            for i in 1...254 { add("\(prefix).\(i)") }
        }
        return hosts
    }

    /// "192.168.1" style prefixes of active private IPv4 interfaces.
    public static func localSubnetPrefixes() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let parts = ip.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 4 else { continue }
            let isPrivate = parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168)
            guard isPrivate else { continue }
            let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"
            if !out.contains(prefix) { out.append(prefix) }
        }
        return out
    }

    /// Scan for the given kinds. Results stream as they are found.
    public static func scan(kinds: [ServiceKind] = ServiceKind.allCases, extraHosts: [String] = [],
                            timeout: Double = 0.7, concurrency: Int = 128) -> AsyncStream<DiscoveredService> {
        AsyncStream { continuation in
            let task = Task {
                let hosts = candidateHosts(extra: extraHosts)
                let ports = Array(Set(kinds.flatMap(ports(for:)))).sorted()
                var targets: [(String, Int)] = []
                for h in hosts { for p in ports { targets.append((h, p)) } }
                var seen = Set<String>()
                await withTaskGroup(of: [DiscoveredService].self) { group in
                    var iterator = targets.makeIterator()
                    func enqueue() -> Bool {
                        guard let (h, p) = iterator.next() else { return false }
                        group.addTask {
                            guard await isOpen(host: h, port: p, timeout: timeout) else { return [] }
                            return await fingerprint(host: h, port: p, kinds: kinds)
                        }
                        return true
                    }
                    for _ in 0..<concurrency { if !enqueue() { break } }
                    while let found = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        for s in found where seen.insert(s.id).inserted { continuation.yield(s) }
                        _ = enqueue()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// TCP connect check with a hard timeout.
    public static func isOpen(host: String, port: Int, timeout: Double) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let gate = OnceGate()
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: if gate.claim() { conn.cancel(); c.resume(returning: true) }
                case .failed, .cancelled, .waiting: if gate.claim() { conn.cancel(); c.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if gate.claim() { conn.cancel(); c.resume(returning: false) }
            }
        }
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    private static func get(_ url: String) async -> (Int, Data)? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: req), let http = resp as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }

    /// Identify what runs on host:port.
    public static func fingerprint(host: String, port: Int, kinds: [ServiceKind] = ServiceKind.allCases) async -> [DiscoveredService] {
        let base = "http://\(host):\(port)"
        var out: [DiscoveredService] = []

        // Servarr apps (Radarr / Sonarr / Prowlarr)
        if kinds.contains(where: { [.radarr, .sonarr, .prowlarr].contains($0) }),
           let (code, data) = await get(base + "/initialize.json"), code == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["apiRoot"] != nil {
            let page = await get(base + "/").map { String(decoding: $0.1, as: UTF8.self) } ?? ""
            let kind: ServiceKind? = page.contains("window.Radarr") || page.contains("<title>Radarr") ? .radarr
                : page.contains("window.Sonarr") || page.contains("<title>Sonarr") ? .sonarr
                : page.contains("window.Prowlarr") || page.contains("<title>Prowlarr") ? .prowlarr
                : (json["apiRoot"] as? String) == "/api/v1" ? .prowlarr : nil
            if let kind, kinds.contains(kind) {
                let urlBase = (json["urlBase"] as? String) ?? ""
                out.append(DiscoveredService(kind: kind, url: base + urlBase, title: (json["instanceName"] as? String) ?? kind.displayName,
                                             version: json["version"] as? String, apiKey: json["apiKey"] as? String, needsLogin: false))
            }
            return out
        }

        // Seerr / Jellyseerr / Overseerr
        if kinds.contains(.seerr), let (code, data) = await get(base + "/api/v1/settings/public"), code == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["applicationTitle"] != nil {
            var version: String?
            if let (c2, d2) = await get(base + "/api/v1/status"), c2 == 200,
               let s = try? JSONSerialization.jsonObject(with: d2) as? [String: Any] { version = s["version"] as? String }
            out.append(DiscoveredService(kind: .seerr, url: base, title: (json["applicationTitle"] as? String) ?? "Seerr",
                                         version: version, apiKey: nil, needsLogin: false))
            return out
        }

        // qBittorrent Web UI
        if kinds.contains(.qbittorrent), let (code, data) = await get(base + "/api/v2/app/version") {
            let body = String(decoding: data, as: UTF8.self)
            if code == 200, body.hasPrefix("v") || body.first?.isNumber == true, body.count < 24 {
                out.append(DiscoveredService(kind: .qbittorrent, url: base, title: "qBittorrent", version: body, apiKey: nil, needsLogin: false))
            } else if code == 403 || code == 401,
                      let page = await get(base + "/").map({ String(decoding: $0.1, as: UTF8.self) }), page.contains("qBittorrent") {
                out.append(DiscoveredService(kind: .qbittorrent, url: base, title: "qBittorrent", version: nil, apiKey: nil, needsLogin: true))
            }
        }
        return out
    }
}

/// Ensures a continuation is resumed once.
final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
