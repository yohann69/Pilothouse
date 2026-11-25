import SwiftUI
import PilothouseKit

struct RequestsView: View {
    let store: SeerrStore
    @State private var filter = SeerrRequestFilter.all
    @State private var sort = "added"
    @State private var requests: [SeerrRequest] = []
    @State private var total = 0
    @State private var state: LoadState = .idle
    @State private var loadingMore = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            StateSwitch(state: state, isEmpty: requests.isEmpty && state != .loaded, retry: { Task { await reload() } }) {
                if requests.isEmpty {
                    ContentUnavailableView("No Requests", systemImage: "tray", description: Text("Nothing matches the “\(filter.label)” filter."))
                } else {
                    ScrollView {
                        counts
                        LazyVStack(spacing: 10) {
                            ForEach(requests) { r in
                                RequestCard(store: store, request: r) { Task { await reload() } }
                                    .onAppear { if r.id == requests.last?.id { Task { await loadMore() } } }
                            }
                            if loadingMore { ProgressView().padding() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Requests")
            .navigationSubtitle("\(total) total")
            .navigationDestination(for: SeerrRoute.self) { SeerrMediaDetailView(store: store, tmdbId: $0.tmdbId, isMovie: $0.isMovie) }
            .toolbar {
                ToolbarItemGroup {
                    Picker("Filter", selection: $filter) {
                        ForEach(SeerrRequestFilter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Sort", selection: $sort) {
                        Text("Recently Added").tag("added")
                        Text("Recently Modified").tag("modified")
                    }
                    .pickerStyle(.menu)
                    Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
        }
        .task(id: "\(filter.rawValue)-\(sort)") { await reload() }
        .focusedSceneValue(\.refreshAction) { Task { await reload() } }
    }

    @ViewBuilder
    private var counts: some View {
        if let c = store.counts {
            HStack(spacing: 10) {
                StatTile(title: "Pending", value: "\(c.pending ?? 0)", symbol: "clock", tint: .orange)
                StatTile(title: "Processing", value: "\(c.processing ?? 0)", symbol: "gearshape.2", tint: .indigo)
                StatTile(title: "Available", value: "\((c.available ?? 0) + (c.completed ?? 0))", symbol: "checkmark.seal", tint: .green)
                StatTile(title: "Movies / Series", value: "\(c.movie ?? 0) / \(c.tv ?? 0)", symbol: "film.stack", tint: .blue)
            }
            .padding(20)
        }
    }

    private func reload() async {
        if requests.isEmpty { state = .loading }
        do {
            let page = try await store.client.requests(filter: filter, take: 30, skip: 0, sort: sort)
            requests = page.results
            total = page.pageInfo.results
            state = .loaded
            await store.loadBasics()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard !loadingMore, requests.count < total else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let page = try? await store.client.requests(filter: filter, take: 30, skip: requests.count, sort: sort) {
            let seen = Set(requests.map(\.id))
            requests += page.results.filter { !seen.contains($0.id) }
        }
    }
}

struct RequestCard: View {
    let store: SeerrStore
    let request: SeerrRequest
    var changed: () -> Void
    @State private var details: SeerrMediaDetails?

    var body: some View {
        let mediaStatus = request.media?.status ?? .unknown
        HStack(alignment: .top, spacing: 14) {
            NavigationLink(value: SeerrRoute(tmdbId: request.tmdbId ?? 0, isMovie: request.isMovie)) {
                RemoteImage([SeerrClient.imageURL(details?.posterPath, size: "w185")], pixelWidth: 160, symbol: request.isMovie ? "film" : "tv")
                    .frame(width: 64, height: 96)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(details?.displayTitle ?? "Loading…").font(.headline).lineLimit(1)
                    if let y = details?.year { Text(y).foregroundStyle(.secondary) }
                    Pill(text: request.isMovie ? "Movie" : "Series", color: request.isMovie ? .yellow : .cyan)
                    if request.is4k == true { Pill(text: "4K", color: .purple) }
                }
                HStack(spacing: 6) {
                    RemoteImage([request.requestedBy?.avatar.flatMap(URL.init(string:))], pixelWidth: 40, symbol: "person")
                        .frame(width: 18, height: 18).clipShape(.circle)
                    Text("\(request.requestedBy?.name ?? "Unknown") · \(Fmt.relative(request.createdAt))")
                    if let m = request.modifiedBy, request.status != .pending, m.id != request.requestedBy?.id { Text("· by \(m.name)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let s = request.seasons, !s.isEmpty {
                    Text("Seasons: " + s.map { String($0.seasonNumber) }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if let st = request.status { Pill(text: st.label, color: st.color, symbol: "tray") }
                    Pill(text: mediaStatus.label, color: mediaStatus.color, symbol: "film")
                    if let dl = request.media?.downloadStatus?.first, let size = dl.size, size > 0 {
                        let p = Double(size - (dl.sizeLeft ?? 0)) / Double(size)
                        Pill(text: "Downloading \(Fmt.percent(p))", color: .blue, symbol: "arrow.down")
                    }
                }
            }
            Spacer()
            RequestButtons(store: store, request: request, changed: changed)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .task(id: request.id) {
            if let tmdb = request.tmdbId { details = await store.details(tmdbId: tmdb, isMovie: request.isMovie) }
        }
    }
}

struct IssuesView: View {
    let store: SeerrStore
    @State private var filter = "open"
    @State private var issues: [SeerrIssue] = []
    @State private var state: LoadState = .idle
    @State private var selected: SeerrIssue?

    var body: some View {
        NavigationStack {
            StateSwitch(state: state, isEmpty: issues.isEmpty && state != .loaded, retry: { Task { await load() } }) {
                if issues.isEmpty {
                    ContentUnavailableView("No Issues", systemImage: "checkmark.bubble", description: Text("No \(filter == "all" ? "" : filter) issues reported."))
                } else {
                    List(issues) { issue in
                        IssueRow(store: store, issue: issue)
                            .contentShape(.rect)
                            .onTapGesture { selected = issue }
                    }
                }
            }
            .navigationTitle("Issues")
            .toolbar {
                ToolbarItemGroup {
                    Picker("Filter", selection: $filter) {
                        Text("Open").tag("open"); Text("Resolved").tag("resolved"); Text("All").tag("all")
                    }
                    .pickerStyle(.segmented)
                    Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
        }
        .task(id: filter) { await load() }
        .focusedSceneValue(\.refreshAction) { Task { await load() } }
        .sheet(item: $selected) { IssueDetailSheet(store: store, issueId: $0.id) { Task { await load() } } }
    }

    private func load() async {
        if issues.isEmpty { state = .loading }
        do {
            issues = try await store.client.issues(filter: filter, take: 100).results
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct IssueRow: View {
    let store: SeerrStore
    let issue: SeerrIssue
    @State private var details: SeerrMediaDetails?

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage([SeerrClient.imageURL(details?.posterPath, size: "w92")], pixelWidth: 100).frame(width: 40, height: 60).clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(details?.displayTitle ?? "…").font(.headline)
                HStack(spacing: 6) {
                    Pill(text: issue.typeLabel, color: .orange)
                    if let s = issue.problemSeason, s > 0 { Text("S\(s)" + ((issue.problemEpisode ?? 0) > 0 ? "E\(issue.problemEpisode!)" : "")) }
                    Text("\(issue.createdBy?.name ?? "") · \(Fmt.relative(issue.createdAt))")
                }
                .font(.caption).foregroundStyle(.secondary)
                if let first = issue.comments?.first?.message { Text(first).font(.callout).lineLimit(2) }
            }
            Spacer()
            Pill(text: issue.isOpen ? "Open" : "Resolved", color: issue.isOpen ? .red : .green)
            Label("\(issue.comments?.count ?? 0)", systemImage: "bubble.left").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .task {
            if let tmdb = issue.media?.tmdbId { details = await store.details(tmdbId: tmdb, isMovie: issue.media?.mediaType == "movie") }
        }
    }
}

struct IssueDetailSheet: View {
    let store: SeerrStore
    let issueId: Int
    var changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var issue: SeerrIssue?
    @State private var comment = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Issue #\(issueId)").font(.title2.bold())
                if let i = issue { Pill(text: i.typeLabel, color: .orange); Pill(text: i.isOpen ? "Open" : "Resolved", color: i.isOpen ? .red : .green) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(issue?.comments ?? []) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.user?.name ?? "").font(.callout.weight(.semibold))
                                Text(Fmt.relative(c.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(c.message).textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                TextField("Add a comment…", text: $comment).textFieldStyle(.roundedBorder)
                Button("Send") {
                    let m = comment
                    app.run("Comment added") {
                        try await store.client.comment(issueId: issueId, message: m)
                        await load()
                    }
                    comment = ""
                }
                .disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            HStack {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Issue", systemImage: "trash") }
                Spacer()
                if let i = issue {
                    Button {
                        app.run(i.isOpen ? "Issue resolved" : "Issue reopened") {
                            try await store.client.setIssue(id: issueId, resolved: i.isOpen)
                            await load()
                            changed()
                        }
                    } label: { Label(i.isOpen ? "Resolve" : "Reopen", systemImage: i.isOpen ? "checkmark.circle" : "arrow.uturn.backward") }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 560, height: 560)
        .task { await load() }
        .confirmationDialog("Delete this issue?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                app.run("Issue deleted") { try await store.client.deleteIssue(id: issueId); changed(); dismiss() }
            }
        }
    }

    private func load() async { issue = try? await store.client.issue(id: issueId) }
}
