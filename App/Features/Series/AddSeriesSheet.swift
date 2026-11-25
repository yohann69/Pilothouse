import SwiftUI
import PilothouseKit

struct AddSeriesSheet: View {
    @Bindable var store: SonarrStore
    var initialTerm: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var results: [JSONValue] = []
    @State private var searching = false
    @State private var error: String?
    @State private var selected: JSONValue?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    AddSeriesOptions(store: store, lookup: selected) { dismiss() } back: { self.selected = nil }
                } else {
                    resultsList
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .frame(width: 760, height: 660)
        .onAppear { if !initialTerm.isEmpty { term = initialTerm; runSearch() } }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search for a series (title, tvdb:123)", text: $term)
                    .textFieldStyle(.plain).font(.title3)
                    .onSubmit { runSearch() }
                    .onChange(of: term) { runSearch(debounce: true) }
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .glassEffect(.regular, in: .capsule)
            .padding()
            if let error {
                ErrorView(message: error) { runSearch() }
            } else if results.isEmpty {
                ContentUnavailableView("Add a Series", systemImage: "play.tv", description: Text("Type a title to search TheTVDB."))
            } else {
                List(Array(results.enumerated()), id: \.offset) { _, r in
                    let tvdb = r["tvdbId"]?.intValue ?? 0
                    let existing = store.series(tvdbId: tvdb)
                    Button { if existing == nil { selected = r } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage([poster(r)], pixelWidth: 140, symbol: "tv").frame(width: 60, height: 90).clipShape(.rect(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r["title"]?.stringValue ?? "").font(.headline)
                                    if let y = r["year"]?.intValue, y > 0 { Text("(\(String(y)))").foregroundStyle(.secondary) }
                                    Spacer()
                                    if existing != nil { Pill(text: "In Library", color: .green, symbol: "checkmark") }
                                }
                                Text(r["overview"]?.stringValue ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                HStack(spacing: 6) {
                                    if let n = r["network"]?.stringValue { Pill(text: n) }
                                    if let c = r["statistics"]?["seasonCount"]?.intValue ?? r["seasons"]?.arrayValue?.count { Pill(text: "\(c) seasons") }
                                    if let s = r["status"]?.stringValue { Pill(text: s.capitalized, color: s == "continuing" ? .green : .secondary) }
                                }
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(existing != nil)
                }
            }
        }
    }

    private func poster(_ r: JSONValue) -> URL? {
        if let s = r["remotePoster"]?.stringValue { return URL(string: s) }
        let img = r["images"]?.arrayValue?.first { $0["coverType"]?.stringValue == "poster" }
        return img?["remoteUrl"]?.stringValue.flatMap(URL.init(string:))
    }

    private func runSearch(debounce: Bool = false) {
        searchTask?.cancel()
        let q = term.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        searchTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(450)) }
            if Task.isCancelled { return }
            searching = true
            defer { searching = false }
            do {
                let r = try await store.client.rawLookup(term: q)
                if !Task.isCancelled { results = r; error = nil }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct AddSeriesOptions: View {
    @Bindable var store: SonarrStore
    let lookup: JSONValue
    var done: () -> Void
    var back: () -> Void
    @Environment(AppModel.self) private var app
    @State private var root = ""
    @State private var profile = 0
    @State private var monitor = SonarrMonitorOption.all
    @State private var seriesType = "standard"
    @State private var seasonFolder = true
    @State private var searchMissing = true
    @State private var searchCutoff = false
    @State private var tags = Set<Int>()
    @State private var adding = false
    @AppStorage("sonarr.lastRoot") private var lastRoot = ""
    @AppStorage("sonarr.lastProfile") private var lastProfile = 0
    @AppStorage("sonarr.lastMonitor") private var lastMonitor = "all"

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage([poster], pixelWidth: 300, symbol: "tv").frame(width: 120, height: 180).clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(lookup["title"]?.stringValue ?? "").font(.title2.bold())
                    if let y = lookup["year"]?.intValue { Text(String(y)).foregroundStyle(.secondary) }
                    Text(lookup["overview"]?.stringValue ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(6)
                }
            }
            .padding()
            Form {
                Picker("Root Folder", selection: $root) {
                    ForEach(store.rootFolders) { f in Text("\(f.path)  (\(Fmt.bytes(f.freeSpace)) free)").tag(f.path) }
                }
                Picker("Monitor", selection: $monitor) {
                    ForEach(SonarrMonitorOption.allCases) { Text($0.label).tag($0) }
                }
                Picker("Quality Profile", selection: $profile) { ForEach(store.profiles) { Text($0.name).tag($0.id) } }
                Picker("Series Type", selection: $seriesType) {
                    Text("Standard").tag("standard"); Text("Daily").tag("daily"); Text("Anime").tag("anime")
                }
                Toggle("Season Folders", isOn: $seasonFolder)
                Toggle("Start search for missing episodes", isOn: $searchMissing)
                Toggle("Start search for cutoff unmet episodes", isOn: $searchCutoff)
                LabeledContent("Tags") {
                    TagPicker(all: store.tags, selected: $tags) { label in
                        try? await store.client.createTag(label).also { t in store.tags.append(t) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Back", action: back)
                Spacer()
                Button { add() } label: {
                    if adding { ProgressView().controlSize(.small) } else { Label("Add Series", systemImage: "plus") }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(adding || root.isEmpty || profile == 0)
            }
            .padding()
        }
        .onAppear {
            root = store.rootFolders.contains { $0.path == lastRoot } ? lastRoot : (store.rootFolders.first?.path ?? "")
            profile = store.profiles.contains { $0.id == lastProfile } ? lastProfile : (store.profiles.first?.id ?? 0)
            monitor = SonarrMonitorOption(rawValue: lastMonitor) ?? .all
            if lookup["seriesType"]?.stringValue == "anime" { seriesType = "anime" }
        }
    }

    private var poster: URL? {
        if let s = lookup["remotePoster"]?.stringValue { return URL(string: s) }
        let img = lookup["images"]?.arrayValue?.first { $0["coverType"]?.stringValue == "poster" }
        return img?["remoteUrl"]?.stringValue.flatMap(URL.init(string:))
    }

    private func add() {
        adding = true
        lastRoot = root; lastProfile = profile; lastMonitor = monitor.rawValue
        let title = lookup["title"]?.stringValue ?? "Series"
        Task {
            do {
                let s = try await store.client.add(lookup: lookup, qualityProfileId: profile, rootFolderPath: root, monitor: monitor,
                                                   seriesType: seriesType, seasonFolder: seasonFolder, tags: Array(tags),
                                                   searchForMissing: searchMissing, searchForCutoffUnmet: searchCutoff)
                store.series.append(s)
                app.flash("Added \(title)")
                done()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            adding = false
        }
    }
}
