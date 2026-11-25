import SwiftUI
import PilothouseKit

struct SeerrMediaDetailView: View {
    let store: SeerrStore
    let tmdbId: Int
    let isMovie: Bool
    @Environment(AppModel.self) private var app
    @State private var details: SeerrMediaDetails?
    @State private var recommendations: [SeerrMediaResult] = []
    @State private var error: String?
    @State private var showRequest = false
    @State private var showIssue = false

    var body: some View {
        Group {
            if let d = details { content(d) }
            else if let error { ErrorView(message: error) { Task { await load() } } }
            else { LoadingView() }
        }
        .task(id: tmdbId) { await load() }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
    }

    private func load() async {
        if let d = await store.details(tmdbId: tmdbId, isMovie: isMovie, force: true) {
            details = d
            error = nil
        } else {
            error = "Couldn't load details from Seerr."
        }
        recommendations = (try? await store.client.recommendations(tmdbId: tmdbId, isMovie: isMovie).results) ?? []
    }

    private func content(_ d: SeerrMediaDetails) -> some View {
        let status = d.mediaInfo?.status ?? .unknown
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackdropHeader(backdrop: [SeerrClient.imageURL(d.backdropPath, size: "w1280")],
                               poster: [SeerrClient.imageURL(d.posterPath, size: "w342")],
                               posterSymbol: isMovie ? "film" : "tv") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(d.displayTitle).font(.largeTitle.bold()).lineLimit(2).shadow(radius: 4)
                        HStack(spacing: 8) {
                            if let y = d.year { Text(y) }
                            if let r = Fmt.runtime(d.runtime ?? d.episodeRunTime?.first) { Text("·"); Text(r) }
                            if let n = d.numberOfSeasons { Text("·"); Text("\(n) season\(n == 1 ? "" : "s")") }
                            if let net = d.networks?.first?.name { Text("·"); Text(net) }
                        }
                        .font(.headline).opacity(0.9)
                        if let g = d.genres, !g.isEmpty { Text(g.map(\.name).joined(separator: ", ")).font(.subheadline).opacity(0.8) }
                        HStack(spacing: 8) {
                            Pill(text: status.label, color: status.color)
                            if let v = d.voteAverage, v > 0 { RatingBadge(source: "TMDB", value: "\(Int(v * 10))%", color: .teal) }
                            if let t = d.tagline, !t.isEmpty { Text("“\(t)”").italic().font(.callout).opacity(0.85) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    actions(d, status: status)
                    if let o = d.overview, !o.isEmpty {
                        Text(o).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: 820, alignment: .leading)
                    }
                    downloads(d)
                    requests(d)
                    if !isMovie { seasons(d) }
                    cast(d)
                    if !recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recommendations").font(.title3.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(recommendations, id: \.uid) { r in
                                        NavigationLink(value: SeerrRoute(tmdbId: r.id, isMovie: r.isMovie)) { SeerrPoster(item: r, width: 120) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .scrollClipDisabled()
                        }
                    }
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(d.displayTitle)
        .sheet(isPresented: $showRequest) {
            SeerrRequestSheet(store: store, details: d, isMovie: isMovie) { Task { await load() } }
        }
        .sheet(isPresented: $showIssue) {
            ReportIssueSheet(store: store, details: d, isMovie: isMovie)
        }
    }

    private func actions(_ d: SeerrMediaDetails, status: SeerrMediaStatus) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                let canRequest = status == .unknown || status == .deleted || (!isMovie && status == .partiallyAvailable) || (!isMovie && status == .processing)
                if canRequest {
                    Button { showRequest = true } label: { Label(status == .unknown ? "Request" : "Request More", systemImage: "plus.circle.fill") }
                        .buttonStyle(.glassProminent)
                } else {
                    Label(status.label, systemImage: status == .available ? "checkmark.circle.fill" : "clock.fill")
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glassEffect(.regular.tint(status.color.opacity(0.3)), in: .capsule)
                }
                if let t = d.trailerURL {
                    Button { NSWorkspace.shared.open(t) } label: { Label("Trailer", systemImage: "play.rectangle.fill") }.buttonStyle(.glass)
                }
                if d.mediaInfo != nil {
                    Button { showIssue = true } label: { Label("Report Issue", systemImage: "exclamationmark.bubble") }.buttonStyle(.glass)
                }
                Menu {
                    Button("Open on TMDB") { openWeb("https://www.themoviedb.org/\(isMovie ? "movie" : "tv")/\(tmdbId)") }
                    if let imdb = d.imdbId { Button("Open on IMDb") { openWeb("https://www.imdb.com/title/\(imdb)") } }
                    if let base = store.client.http.baseURL { Button("Open in Seerr") { openWeb("\(base.absoluteString)/\(isMovie ? "movie" : "tv")/\(tmdbId)") } }
                    if let h = d.homepage, !h.isEmpty { Button("Homepage") { openWeb(h) } }
                } label: { Label("More", systemImage: "ellipsis") }
                    .menuStyle(.button).buttonStyle(.glass).fixedSize()
            }
        }
    }

    @ViewBuilder
    private func downloads(_ d: SeerrMediaDetails) -> some View {
        if let dl = d.mediaInfo?.downloadStatus, !dl.isEmpty {
            GlassCard(title: "Downloading", symbol: "arrow.down.circle", tint: .blue) {
                ForEach(Array(dl.enumerated()), id: \.offset) { _, s in
                    let size = Double(s.size ?? 0), left = Double(s.sizeLeft ?? 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title ?? "").lineLimit(1)
                        HStack {
                            LinearProgress(value: size > 0 ? (size - left) / size : 0, tint: .blue)
                            Text(s.timeLeft ?? "").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func requests(_ d: SeerrMediaDetails) -> some View {
        if let reqs = d.mediaInfo?.requests, !reqs.isEmpty {
            GlassCard(title: "Requests", symbol: "tray.and.arrow.down", tint: .indigo) {
                ForEach(reqs) { r in
                    RequestActionsRow(store: store, request: r) { Task { await load() } }
                }
            }
        }
    }

    private func seasons(_ d: SeerrMediaDetails) -> some View {
        GlassCard(title: "Seasons", symbol: "square.stack") {
            ForEach(d.requestableSeasons) { s in
                let st = d.mediaInfo?.seasons?.first { $0.seasonNumber == s.seasonNumber }?.status.flatMap(SeerrMediaStatus.init) ?? .unknown
                HStack {
                    Text(s.name ?? "Season \(s.seasonNumber)")
                    Text("\(s.episodeCount ?? 0) episodes").font(.caption).foregroundStyle(.secondary)
                    if let a = s.airDate { Text(a).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Pill(text: st.label, color: st.color)
                }
            }
        }
    }

    @ViewBuilder
    private func cast(_ d: SeerrMediaDetails) -> some View {
        if let cast = d.credits?.cast, !cast.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cast").font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(cast.prefix(20)) { c in
                            VStack(spacing: 6) {
                                RemoteImage([SeerrClient.imageURL(c.profilePath, size: "w185")], pixelWidth: 200, symbol: "person")
                                    .frame(width: 84, height: 84)
                                    .clipShape(.circle)
                                Text(c.name).font(.caption.weight(.medium)).lineLimit(1)
                                Text(c.character ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 96)
                        }
                    }
                }
            }
        }
    }
}

/// Request row with approve/decline/delete controls.
struct RequestActionsRow: View {
    let store: SeerrStore
    let request: SeerrRequest
    var changed: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage([request.requestedBy?.avatar.flatMap(URL.init(string:))], pixelWidth: 60, symbol: "person")
                .frame(width: 26, height: 26).clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.requestedBy?.name ?? "Unknown").font(.callout)
                HStack(spacing: 6) {
                    Text(Fmt.relative(request.createdAt))
                    if request.is4k == true { Text("· 4K") }
                    if let s = request.seasons, !s.isEmpty { Text("· Seasons \(s.map { String($0.seasonNumber) }.joined(separator: ", "))") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let st = request.status { Pill(text: st.label, color: st.color) }
            RequestButtons(store: store, request: request, changed: changed)
        }
    }
}

struct RequestButtons: View {
    let store: SeerrStore
    let request: SeerrRequest
    var changed: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            if request.status == .pending {
                Button {
                    app.run("Request approved") { try await store.client.approve(requestId: request.id); changed(); await store.loadBasics() }
                } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.glassProminent).tint(.green).help("Approve")
                Button {
                    app.run("Request declined") { try await store.client.decline(requestId: request.id); changed(); await store.loadBasics() }
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glassProminent).tint(.red).help("Decline")
            }
            if request.status == .failed {
                Button {
                    app.run("Retrying request") { try await store.client.retry(requestId: request.id); changed() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.glass).help("Retry")
            }
            Menu {
                if request.status == .pending {
                    Button("Approve") { app.run("Approved") { try await store.client.approve(requestId: request.id); changed() } }
                    Button("Decline") { app.run("Declined") { try await store.client.decline(requestId: request.id); changed() } }
                }
                if request.status == .failed || request.status == .approved {
                    Button("Retry") { app.run("Retrying") { try await store.client.retry(requestId: request.id); changed() } }
                }
                Divider()
                Button("Delete Request", role: .destructive) {
                    app.run("Request deleted") { try await store.client.deleteRequest(id: request.id); changed(); await store.loadBasics() }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).buttonStyle(.glass).fixedSize()
        }
    }
}

struct SeerrRequestSheet: View {
    let store: SeerrStore
    let details: SeerrMediaDetails
    let isMovie: Bool
    var done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.seerrDefault4K) private var default4K = false
    @State private var seasons = Set<Int>()
    @State private var is4k = false
    @State private var servers: [SeerrServiceServer] = []
    @State private var serverId: Int?
    @State private var service: SeerrServiceDetails?
    @State private var profileId: Int?
    @State private var rootFolder: String?
    @State private var sending = false

    private var unavailableSeasons: Set<Int> {
        var s = Set<Int>()
        for st in details.mediaInfo?.seasons ?? [] where (st.status ?? 1) > 1 { s.insert(st.seasonNumber) }
        for r in details.mediaInfo?.requests ?? [] where r.status != .declined {
            for rs in r.seasons ?? [] { s.insert(rs.seasonNumber) }
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                RemoteImage([SeerrClient.imageURL(details.posterPath, size: "w185")], pixelWidth: 200).frame(width: 60, height: 90).clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text("Request \(isMovie ? "Movie" : "Series")").font(.caption).foregroundStyle(.secondary)
                    Text(details.displayTitle).font(.title2.bold())
                }
            }
            .padding()
            Form {
                if !isMovie {
                    SwiftUI.Section {
                        ForEach(details.requestableSeasons) { s in
                            let taken = unavailableSeasons.contains(s.seasonNumber)
                            Toggle(isOn: Binding(get: { taken || seasons.contains(s.seasonNumber) }, set: { on in
                                if on { seasons.insert(s.seasonNumber) } else { seasons.remove(s.seasonNumber) }
                            })) {
                                HStack {
                                    Text(s.name ?? "Season \(s.seasonNumber)")
                                    Text("\(s.episodeCount ?? 0) eps").foregroundStyle(.secondary).font(.caption)
                                    if taken { Text("Already requested/available").font(.caption).foregroundStyle(.orange) }
                                }
                            }
                            .disabled(taken)
                        }
                    } header: {
                        HStack {
                            Text("Seasons")
                            Spacer()
                            Button("Select All") { seasons = Set(details.requestableSeasons.map(\.seasonNumber)).subtracting(unavailableSeasons) }
                                .buttonStyle(.link)
                        }
                    }
                }
                SwiftUI.Section("Options") {
                    if servers.contains(where: \.is4k) {
                        Toggle("Request in 4K", isOn: $is4k)
                    }
                    Picker("Server", selection: $serverId) {
                        ForEach(servers.filter { $0.is4k == is4k }) { s in Text(s.name + (s.isDefault ? " (default)" : "")).tag(Optional(s.id)) }
                    }
                    if let service {
                        Picker("Quality Profile", selection: $profileId) {
                            ForEach(service.profiles) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Picker("Root Folder", selection: $rootFolder) {
                            ForEach(service.rootFolders) { f in Text("\(f.path) (\(Fmt.bytes(f.freeSpace)) free)").tag(Optional(f.path)) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { send() } label: {
                    if sending { ProgressView().controlSize(.small) } else { Label("Request", systemImage: "paperplane.fill") }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sending || (!isMovie && seasons.isEmpty))
            }
            .padding()
        }
        .frame(width: 520, height: isMovie ? 420 : 620)
        .task {
            is4k = default4K
            servers = (try? await (isMovie ? store.client.radarrServers() : store.client.sonarrServers())) ?? []
            selectDefaultServer()
        }
        .onChange(of: is4k) { selectDefaultServer() }
        .onChange(of: serverId) { Task { await loadService() } }
    }

    private func selectDefaultServer() {
        let candidates = servers.filter { $0.is4k == is4k }
        serverId = (candidates.first { $0.isDefault } ?? candidates.first)?.id
    }

    private func loadService() async {
        guard let serverId else { service = nil; return }
        service = try? await store.client.serviceDetails(isMovie: isMovie, serverId: serverId)
        let server = servers.first { $0.id == serverId }
        profileId = server?.activeProfileId ?? service?.profiles.first?.id
        rootFolder = server?.activeDirectory ?? service?.rootFolders.first?.path
    }

    private func send() {
        sending = true
        let s = Array(seasons).sorted()
        Task {
            do {
                try await store.client.request(tmdbId: details.id, isMovie: isMovie, seasons: s, is4k: is4k,
                                               serverId: serverId, profileId: profileId, rootFolder: rootFolder)
                app.flash("Requested \(details.displayTitle)")
                await store.loadBasics()
                done()
                dismiss()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            sending = false
        }
    }
}

struct ReportIssueSheet: View {
    let store: SeerrStore
    let details: SeerrMediaDetails
    let isMovie: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var type = 1
    @State private var message = ""
    @State private var season = 0
    @State private var episode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Report an Issue — \(details.displayTitle)").font(.title3.bold())
            Picker("Type", selection: $type) {
                Text("Video").tag(1); Text("Audio").tag(2); Text("Subtitles").tag(3); Text("Other").tag(4)
            }
            .pickerStyle(.segmented)
            if !isMovie {
                HStack {
                    Picker("Season", selection: $season) {
                        Text("All").tag(0)
                        ForEach(details.requestableSeasons) { Text("Season \($0.seasonNumber)").tag($0.seasonNumber) }
                    }
                    Stepper("Episode \(episode == 0 ? "All" : String(episode))", value: $episode, in: 0...200)
                }
            }
            TextEditor(text: $message).frame(height: 120).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Submit") {
                    guard let mediaId = details.mediaInfo?.id else { return }
                    let (t, m, s, e) = (type, message, season, episode)
                    app.run("Issue reported") { try await store.client.createIssue(mediaId: mediaId, issueType: t, message: m, season: s, episode: e) }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
