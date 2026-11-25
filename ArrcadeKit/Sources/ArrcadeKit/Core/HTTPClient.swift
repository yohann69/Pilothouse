import Foundation
import Synchronization

public enum APIError: LocalizedError, Sendable, Equatable {
    case notConfigured(String)
    case invalidURL(String)
    case http(status: Int, message: String)
    case unauthorized(String)
    case decoding(String)
    case network(String)
    case loginFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let s): "\(s) is not configured."
        case .invalidURL(let s): "Invalid URL: \(s)"
        case .http(let status, let message):
            message.isEmpty ? "Server returned HTTP \(status)." : "HTTP \(status): \(message)"
        case .unauthorized(let s): "Unauthorized — check the API key / credentials for \(s)."
        case .decoding(let s): "Unexpected response: \(s)"
        case .network(let s): s
        case .loginFailed(let s): "Login failed: \(s)"
        }
    }
}

public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

public enum RequestBody: Sendable {
    case none
    case json(Data)
    case form([(String, String)])
    case multipart(boundary: String, data: Data)

    public static func encode<T: Encodable>(_ value: T) throws -> RequestBody {
        .json(try JSONCoding.encoder.encode(value))
    }
}

/// Strict RFC 3986 query encoding (Seerr rejects unescaped `!'()*`).
enum QueryEncoding {
    static let allowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
    static func encode(_ items: [(String, String)]) -> String {
        items.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&")
    }
}

final class InsecureTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

/// Low-level HTTP transport shared by all service clients.
/// Handles base-URL fallback, custom headers, strict query encoding and error mapping.
public final class HTTPClient: Sendable {
    public let config: ServiceConfig
    let session: URLSession
    private let activeIndex = Mutex<Int>(0)
    private let authHeaders: [String: String]

    public init(config: ServiceConfig, authHeaders: [String: String] = [:], ephemeralCookies: Bool = false) {
        self.config = config
        self.authHeaders = authHeaders
        let cfg = ephemeralCookies ? URLSessionConfiguration.ephemeral : URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = config.timeout
        cfg.timeoutIntervalForResource = max(config.timeout * 6, 120)
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.waitsForConnectivity = false
        if ephemeralCookies {
            cfg.httpShouldSetCookies = true
            cfg.httpCookieAcceptPolicy = .always
        } else {
            cfg.httpShouldSetCookies = false
        }
        if config.allowInvalidCertificates {
            session = URLSession(configuration: cfg, delegate: InsecureTrustDelegate(), delegateQueue: nil)
        } else {
            session = URLSession(configuration: cfg)
        }
    }

    deinit { session.invalidateAndCancel() }

    public var baseURL: URL? {
        let urls = config.baseURLs
        guard !urls.isEmpty else { return nil }
        return urls[min(activeIndex.withLock { $0 }, urls.count - 1)]
    }

    public func url(path: String, query: [(String, String)] = []) throws -> URL {
        guard let base = baseURL else { throw APIError.notConfigured(config.name) }
        return try Self.build(base: base, path: path, query: query)
    }

    static func build(base: URL, path: String, query: [(String, String)]) throws -> URL {
        var s = base.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        s += path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { s += (s.contains("?") ? "&" : "?") + QueryEncoding.encode(query) }
        guard let url = URL(string: s) else { throw APIError.invalidURL(s) }
        return url
    }

    func makeRequest(base: URL, method: HTTPMethod, path: String, query: [(String, String)],
                     body: RequestBody, extraHeaders: [String: String]) throws -> URLRequest {
        var req = URLRequest(url: try Self.build(base: base, path: path, query: query))
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in authHeaders { req.setValue(v, forHTTPHeaderField: k) }
        for h in config.customHeaders where !h.name.isEmpty { req.setValue(h.value, forHTTPHeaderField: h.name) }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        switch body {
        case .none: break
        case .json(let d):
            req.httpBody = d
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .form(let items):
            req.httpBody = Data(QueryEncoding.encode(items).utf8)
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        case .multipart(let boundary, let d):
            req.httpBody = d
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Perform a request, transparently falling back to the alternate base URL on connectivity errors.
    @discardableResult
    public func send(_ method: HTTPMethod = .get, _ path: String, query: [(String, String)] = [],
                     body: RequestBody = .none, headers: [String: String] = [:],
                     acceptStatus: (Int) -> Bool = { (200..<300).contains($0) }) async throws -> (Data, HTTPURLResponse) {
        let urls = config.baseURLs
        guard !urls.isEmpty else { throw APIError.notConfigured(config.name) }
        let start = activeIndex.withLock { min($0, urls.count - 1) }
        let order = [start] + urls.indices.filter { $0 != start }
        var lastError: Error = APIError.network("Unreachable")
        for idx in order {
            let req = try makeRequest(base: urls[idx], method: method, path: path, query: query, body: body, extraHeaders: headers)
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw APIError.network("Invalid response") }
                if idx != start { activeIndex.withLock { $0 = idx } }
                if acceptStatus(http.statusCode) { return (data, http) }
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw APIError.unauthorized(config.name)
                }
                throw APIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
            } catch let e as URLError where Self.isConnectivity(e) {
                lastError = APIError.network("\(config.name): \(e.localizedDescription)")
                continue
            } catch let e as URLError {
                throw APIError.network("\(config.name): \(e.localizedDescription)")
            }
        }
        throw lastError
    }

    public func decode<T: Decodable>(_ type: T.Type, _ method: HTTPMethod = .get, _ path: String,
                                     query: [(String, String)] = [], body: RequestBody = .none) async throws -> T {
        let (data, _) = try await send(method, path, query: query, body: body)
        return try Self.decode(T.self, from: data, path: path)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw APIError.decoding("\(path): missing '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(t, ctx) {
            throw APIError.decoding("\(path): type mismatch \(t) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.valueNotFound(t, ctx) {
            throw APIError.decoding("\(path): null \(t) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.dataCorrupted(ctx) {
            let snippet = String(decoding: data.prefix(120), as: UTF8.self)
            throw APIError.decoding("\(path): \(ctx.debugDescription) \(ctx.codingPath.map(\.stringValue).joined(separator: ".")) — \(snippet)")
        }
    }

    static func isConnectivity(_ e: URLError) -> Bool {
        switch e.code {
        case .cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost, .dnsLookupFailed,
             .notConnectedToInternet, .secureConnectionFailed, .cannotLoadFromNetwork, .internationalRoamingOff:
            return true
        default: return false
        }
    }

    static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] {
                for key in ["message", "error", "errorMessage", "title"] {
                    if let m = dict[key] as? String, !m.isEmpty { return m }
                }
            }
            if let arr = json as? [[String: Any]] {
                let msgs = arr.compactMap { $0["errorMessage"] as? String }
                if !msgs.isEmpty { return msgs.joined(separator: "\n") }
            }
        }
        let s = String(decoding: data.prefix(300), as: UTF8.self)
        return s.contains("<html") ? "" : s
    }
}

public extension Int64 {
    /// Human readable byte count ("1.2 GB").
    var byteString: String {
        if self <= 0 { return "0 B" }
        if self < 1000 { return "\(self) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var v = Double(self) / 1000
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        let digits = v < 10 ? 2 : v < 100 ? 1 : 0
        return v.formatted(.number.precision(.fractionLength(digits))) + " " + units[i]
    }
}

public extension Int {
    var byteString: String { Int64(self).byteString }
    var speedString: String { Int64(self).byteString + "/s" }
}
