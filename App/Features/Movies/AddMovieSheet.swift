import SwiftUI
import PilothouseKit

/// Search TMDB through Radarr's lookup and add a movie with full options.
struct AddMovieSheet: View {
    @Bindable var store: RadarrStore
    var initialTerm: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
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
                    AddMovieOptions(store: store, lookup: selected) { dismiss() } back: { self.selected = nil }
                } else {
                    resultsList
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .frame(width: 760, height: 620)
        .onAppear {
            if !initialTerm.isEmpty { term = initialTerm; runSearch() }
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search for a movie (title, tmdb:123, imdb:tt…)", text: $term)
                    .textFieldStyle(.plain)
                    .font(.title3)
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
                ContentUnavailableView("Add a Movie", systemImage: "film.stack", description: Text("Type a title to search The Movie Database."))
            } else {
                List(Array(results.enumerated()), id: \.offset) { _, r in
                    let tmdb = r["tmdbId"]?.intValue ?? 0
                    let existing = store.movie(tmdbId: tmdb)
                    Button {
                        if existing == nil { selected = r }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage([posterURL(r)], pixelWidth: 140).frame(width: 60, height: 90).clipShape(.rect(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r["title"]?.stringValue ?? "").font(.headline)
                                    if let y = r["year"]?.intValue, y > 0 { Text("(\(String(y)))").foregroundStyle(.secondary) }
                                    Spacer()
                                    if existing != nil { Pill(text: "In Library", color: .green, symbol: "checkmark") }
                                }
                                Text(r["overview"]?.stringValue ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                HStack(spacing: 6) {
                                    if let s = r["studio"]?.stringValue, !s.isEmpty { Pill(text: s) }
                                    if let rt = r["runtime"]?.intValue, let f = Fmt.runtime(rt) { Pill(text: f) }
                                    if let g = r["genres"]?.arrayValue?.compactMap(\.stringValue).prefix(3), !g.isEmpty { Pill(text: g.joined(separator: ", ")) }
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

    private func posterURL(_ r: JSONValue) -> URL? {
        if let s = r["remotePoster"]?.stringValue { return URL(string: s.replacingOccurrences(of: "/original/", with: "/w185/")) }
        let img = r["images"]?.arrayValue?.first { $0["coverType"]?.stringValue == "poster" }
        return img?["remoteUrl"]?.stringValue.flatMap { URL(string: $0.replacingOccurrences(of: "/original/", with: "/w185/")) }
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

struct AddMovieOptions: View {
    @Bindable var store: RadarrStore
    let lookup: JSONValue
    var done: () -> Void
    var back: () -> Void
    @Environment(AppModel.self) private var app
    @State private var root = ""
    @State private var profile = 0
    @State private var monitored = true
    @State private var availability = "released"
    @State private var search = true
    @State private var tags = Set<Int>()
    @State private var adding = false
    @AppStorage("radarr.lastRoot") private var lastRoot = ""
    @AppStorage("radarr.lastProfile") private var lastProfile = 0
    @AppStorage("radarr.lastAvailability") private var lastAvailability = "released"

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage([posterURL], pixelWidth: 300).frame(width: 120, height: 180).clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(lookup["title"]?.stringValue ?? "").font(.title2.bold())
                    if let y = lookup["year"]?.intValue { Text(String(y)).foregroundStyle(.secondary) }
                    Text(lookup["overview"]?.stringValue ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(6)
                }
            }
            .padding()
            Form {
                Picker("Root Folder", selection: $root) {
                    ForEach(store.rootFolders) { f in
                        Text("\(f.path)  (\(Fmt.bytes(f.freeSpace)) free)").tag(f.path)
                    }
                }
                Picker("Quality Profile", selection: $profile) {
                    ForEach(store.profiles) { Text($0.name).tag($0.id) }
                }
                Picker("Minimum Availability", selection: $availability) {
                    ForEach(RadarrAvailability.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Monitored", isOn: $monitored)
                Toggle("Start search for missing movie", isOn: $search)
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
                Button {
                    add()
                } label: {
                    if adding { ProgressView().controlSize(.small) } else { Label("Add Movie", systemImage: "plus") }
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
            availability = lastAvailability
        }
    }

    private var posterURL: URL? {
        let img = lookup["images"]?.arrayValue?.first { $0["coverType"]?.stringValue == "poster" }
        return (lookup["remotePoster"]?.stringValue ?? img?["remoteUrl"]?.stringValue).flatMap { URL(string: $0.replacingOccurrences(of: "/original/", with: "/w342/")) }
    }

    private func add() {
        adding = true
        lastRoot = root; lastProfile = profile; lastAvailability = availability
        let title = lookup["title"]?.stringValue ?? "Movie"
        Task {
            do {
                let m = try await store.client.add(lookup: lookup, qualityProfileId: profile, rootFolderPath: root, monitored: monitored,
                                                   minimumAvailability: availability, tags: Array(tags), searchForMovie: search)
                store.movies.append(m)
                app.flash("Added \(title)" + (search ? " — searching" : ""))
                done()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            adding = false
        }
    }
}
