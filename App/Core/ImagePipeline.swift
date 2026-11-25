import SwiftUI
import ImageIO

/// Memory + disk cached, downsampled image loading. Decoding happens off the main thread
/// and requests for the same URL are coalesced.
nonisolated final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let memory: NSCache<NSString, CGImageBox> = {
        let c = NSCache<NSString, CGImageBox>()
        c.totalCostLimit = 256 * 1024 * 1024
        return c
    }()
    private let session: URLSession
    private let inflight = InflightRegistry()

    final class CGImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ i: CGImage) { image = i }
    }

    private init() {
        let cfg = URLSessionConfiguration.default
        let dir = URL.cachesDirectory.appending(path: "pilothouse-images")
        cfg.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024, directory: dir)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    func cached(_ url: URL, pixelWidth: Int) -> CGImage? {
        memory.object(forKey: key(url, pixelWidth))?.image
    }

    private func key(_ url: URL, _ w: Int) -> NSString { "\(w)|\(url.absoluteString)" as NSString }

    func image(for url: URL, pixelWidth: Int) async -> CGImage? {
        let k = key(url, pixelWidth)
        if let hit = memory.object(forKey: k) { return hit.image }
        let task = await inflight.task(for: k as String) { [session] in
            do {
                var req = URLRequest(url: url)
                req.cachePolicy = .returnCacheDataElseLoad
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                return Self.downsample(data, maxPixel: pixelWidth).map(CGImageBox.init)
            } catch { return nil }
        }
        let result = await task.value
        await inflight.finish(k as String)
        if let result {
            memory.setObject(result, forKey: k, cost: result.image.bytesPerRow * result.image.height)
        }
        return result?.image
    }

    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel)
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts)
    }

    actor InflightRegistry {
        private var tasks: [String: Task<CGImageBox?, Never>] = [:]
        func task(for key: String, _ make: @escaping @Sendable () async -> CGImageBox?) -> Task<CGImageBox?, Never> {
            if let t = tasks[key] { return t }
            let t = Task { await make() }
            tasks[key] = t
            return t
        }
        func finish(_ key: String) { tasks[key] = nil }
    }
}

/// Async image view backed by `ImagePipeline`. Tries each candidate URL in order.
struct RemoteImage<Placeholder: View>: View {
    let urls: [URL]
    var contentMode: ContentMode = .fill
    var pixelWidth: Int = 400
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?
    @State private var loadedKey: String?

    init(_ urls: [URL?], contentMode: ContentMode = .fill, pixelWidth: Int = 400,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.urls = urls.compactMap { $0 }
        self.contentMode = contentMode
        self.pixelWidth = pixelWidth
        self.placeholder = placeholder
    }

    private var key: String { urls.map(\.absoluteString).joined(separator: "|") + "@\(pixelWidth)" }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            if loadedKey == key, image != nil { return }
            if let first = urls.first, let hit = ImagePipeline.shared.cached(first, pixelWidth: pixelWidth) {
                image = hit; loadedKey = key; return
            }
            image = nil
            for url in urls {
                if Task.isCancelled { return }
                if let img = await ImagePipeline.shared.image(for: url, pixelWidth: pixelWidth) {
                    withAnimation(.easeOut(duration: 0.18)) { image = img }
                    loadedKey = key
                    return
                }
            }
        }
    }
}

extension RemoteImage where Placeholder == PosterPlaceholder {
    init(_ urls: [URL?], contentMode: ContentMode = .fill, pixelWidth: Int = 400, symbol: String = "photo") {
        self.init(urls, contentMode: contentMode, pixelWidth: pixelWidth) { PosterPlaceholder(symbol: symbol) }
    }
}

struct PosterPlaceholder: View {
    var symbol: String = "photo"
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }
}
