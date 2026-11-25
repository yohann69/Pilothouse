import SwiftUI
import ArrcadeKit

struct SeerrRoute: Hashable {
    let tmdbId: Int
    let isMovie: Bool
}

struct SeerrCategoryRoute: Hashable {
    let category: SeerrDiscoverCategory
}

struct DiscoverView: View {
    let store: SeerrStore
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var rows: [SeerrDiscoverCategory: [SeerrMediaResult]] = [:]
    @State private var errors: [SeerrDiscoverCategory: String] = [:]
    @State private var loaded = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    SeerrGrid(store: store, loader: { page in try await store.client.search(search, page: page) }, key: "search:\(search)")
                } else {
                    carousels
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $search, placement: .toolbar, prompt: "Search movies, series & people")
            .navigationDestination(for: SeerrRoute.self) { SeerrMediaDetailView(store: store, tmdbId: $0.tmdbId, isMovie: $0.isMovie) }
            .navigationDestination(for: SeerrCategoryRoute.self) { r in
                SeerrGrid(store: store, loader: { page in try await store.client.discover(r.category, page: page) }, key: r.category.rawValue)
                    .navigationTitle(r.category.label)
            }
            .toolbar {
                ToolbarItem { Button { Task { await load(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            }
        }
        .task { await load(force: false) }
        .focusedSceneValue(\.refreshAction) { Task { await load(force: true) } }
    }

    private var carousels: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(SeerrDiscoverCategory.allCases) { cat in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(cat.label).font(.title2.bold())
                            Spacer()
                            NavigationLink(value: SeerrCategoryRoute(category: cat)) { Text("See All") }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 24)
                        if let e = errors[cat] {
                            Text(e).foregroundStyle(.red).padding(.horizontal, 24)
                        } else if let items = rows[cat] {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 16) {
                                    ForEach(items.filter { !$0.isPerson }, id: \.uid) { item in
                                        NavigationLink(value: SeerrRoute(tmdbId: item.id, isMovie: item.isMovie)) {
                                            SeerrPoster(item: item, width: 150)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 6)
                            }
                            .scrollClipDisabled()
                        } else {
                            ProgressView().padding(.horizontal, 24).frame(height: 240)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    private func load(force: Bool) async {
        if loaded && !force { return }
        loaded = true
        await withTaskGroup(of: (SeerrDiscoverCategory, Result<[SeerrMediaResult], Error>).self) { group in
            for cat in SeerrDiscoverCategory.allCases {
                let client = store.client
                group.addTask {
                    do { return (cat, .success(try await client.discover(cat).results)) } catch { return (cat, .failure(error)) }
                }
            }
            for await (cat, result) in group {
                switch result {
                case .success(let r): rows[cat] = r; errors[cat] = nil
                case .failure(let e): errors[cat] = e.localizedDescription
                }
            }
        }
    }
}

/// Poster with availability badge.
struct SeerrPoster: View {
    let item: SeerrMediaResult
    var width: CGFloat = 150

    var body: some View {
        PosterTile(urls: [SeerrClient.imageURL(item.posterPath ?? item.profilePath, size: width > 160 ? "w342" : "w185")],
                   title: item.displayTitle, subtitle: [item.year, item.isMovie ? "Movie" : item.isTV ? "Series" : "Person"].compactMap { $0 }.joined(separator: " · "),
                   width: width, symbol: item.isPerson ? "person" : item.isMovie ? "film" : "tv") {
            if let status = item.mediaInfo?.status, status != .unknown {
                Image(systemName: status == .available ? "checkmark" : status == .partiallyAvailable ? "minus" : "clock")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .glassEffect(.regular.tint(status.color), in: .circle)
                    .help(status.label)
            }
        }
    }
}

/// Infinite-scrolling grid for search & category pages.
struct SeerrGrid: View {
    let store: SeerrStore
    let loader: (Int) async throws -> SeerrDiscoverPage
    let key: String
    @AppStorage(Prefs.posterSize) private var posterSize = PosterSize.medium
    @State private var items: [SeerrMediaResult] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let error, items.isEmpty {
                ErrorView(message: error) { Task { await reset() } }.frame(minHeight: 400)
            } else if items.isEmpty && !loading && page > 0 {
                ContentUnavailableView.search
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: posterSize.width, maximum: posterSize.width + 24), spacing: 18)], spacing: 22) {
                ForEach(items, id: \.uid) { item in
                    if item.isPerson {
                        SeerrPoster(item: item, width: posterSize.width)
                    } else {
                        NavigationLink(value: SeerrRoute(tmdbId: item.id, isMovie: item.isMovie)) {
                            SeerrPoster(item: item, width: posterSize.width)
                        }
                        .buttonStyle(.plain)
                        .onAppear { if item.uid == items.last?.uid { Task { await next() } } }
                    }
                }
            }
            .padding(20)
            if loading { ProgressView().padding() }
        }
        .task(id: key) {
            try? await Task.sleep(for: .milliseconds(key.hasPrefix("search:") ? 350 : 0))
            if Task.isCancelled { return }
            await reset()
        }
    }

    private func reset() async {
        items = []; page = 0; totalPages = 1; error = nil
        await next()
    }

    private func next() async {
        guard !loading, page < totalPages else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await loader(page + 1)
            if Task.isCancelled { return }
            page = p.page
            totalPages = p.totalPages
            let seen = Set(items.map(\.uid))
            items += p.results.filter { !seen.contains($0.uid) }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
