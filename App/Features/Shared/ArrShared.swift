import SwiftUI
import PilothouseKit

/// Interactive search: lists releases from all indexers and lets the user grab one.
struct ReleasesSheet: View {
    var title: String
    var load: () async throws -> [ArrRelease]
    var grab: (ArrRelease) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var releases: [ArrRelease] = []
    @State private var state: LoadState = .idle
    @State private var sortOrder = [KeyPathComparator(\ReleaseRow.weight)]
    @State private var filter = ""
    @State private var hideRejected = false
    @State private var protocolFilter = "all"
    @State private var selection: ReleaseRow.ID?
    @State private var grabbing: Set<String> = []
    @State private var confirmRejected: ArrRelease?

    nonisolated struct ReleaseRow: Identifiable {
        let r: ArrRelease
        var id: String { r.id }
        var weight: Int { r.releaseWeight ?? 0 }
        var title: String { r.title }
        var indexer: String { r.indexer ?? "" }
        var size: Int64 { r.size ?? 0 }
        var age: Double { r.ageMinutes ?? Double(r.age ?? 0) * 1440 }
        var seeders: Int { r.seeders ?? -1 }
        var quality: String { r.quality?.name ?? "" }
        var score: Int { r.customFormatScore ?? 0 }
    }

    private var rows: [ReleaseRow] {
        releases.map(ReleaseRow.init)
            .filter { !hideRejected || $0.r.rejected != true }
            .filter { protocolFilter == "all" || $0.r.protocol?.lowercased() == protocolFilter }
            .filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.indexer.localizedCaseInsensitiveContains(filter) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Interactive Search").font(.title2.bold())
                    Text(title).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Protocol", selection: $protocolFilter) {
                    Text("All").tag("all")
                    Text("Torrent").tag("torrent")
                    Text("Usenet").tag("usenet")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle("Hide rejected", isOn: $hideRejected).toggleStyle(.checkbox)
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            Group {
                if state.isLoading {
                    LoadingView(label: "Searching indexers… this can take a while")
                } else if let e = state.error {
                    ErrorView(message: e) { Task { await reload() } }
                } else if releases.isEmpty {
                    ContentUnavailableView("No Releases Found", systemImage: "magnifyingglass", description: Text("No indexer returned results."))
                } else {
                    table
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("\(rows.count) of \(releases.count) releases").foregroundStyle(.secondary).font(.callout)
                Spacer()
                Button {
                    if let sel = selection, let r = releases.first(where: { $0.id == sel }) { attemptGrab(r) }
                } label: { Label("Download", systemImage: "arrow.down.circle") }
                .buttonStyle(.glassProminent)
                .disabled(selection == nil)
            }
            .padding()
        }
        .frame(minWidth: 860, idealWidth: 1200, maxWidth: .infinity, minHeight: 520, idealHeight: 680, maxHeight: .infinity)
        .task { await reload() }
        .confirmationDialog("This release was rejected", isPresented: Binding(get: { confirmRejected != nil }, set: { if !$0 { confirmRejected = nil } }), presenting: confirmRejected) { r in
            Button("Download Anyway") { doGrab(r) }
        } message: { r in
            Text((r.rejections ?? []).joined(separator: "\n"))
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { row in
                Image(systemName: row.r.isTorrent ? "arrow.down.doc" : "newspaper")
                    .foregroundStyle(row.r.isTorrent ? .green : .blue)
                    .help(row.r.protocol ?? "")
            }
            .width(22)
            TableColumn("Age", value: \.age) { row in Text(Fmt.age(hours: row.age / 60)).monospacedDigit() }.width(50)
            TableColumn("Title", value: \.title) { row in
                Text(row.title).lineLimit(2).help(row.title)
            }
            .width(min: 300, ideal: 460)
            TableColumn("Indexer", value: \.indexer).width(min: 70, ideal: 110)
            TableColumn("Size", value: \.size) { row in Text(row.size.byteString).monospacedDigit() }.width(75)
            TableColumn("Peers", value: \.seeders) { row in
                if row.r.isTorrent {
                    Text("\(row.r.seeders ?? 0)/\(row.r.leechers ?? 0)")
                        .monospacedDigit()
                        .foregroundStyle((row.r.seeders ?? 0) > 10 ? .green : (row.r.seeders ?? 0) > 0 ? .orange : .red)
                } else { Text("—").foregroundStyle(.tertiary) }
            }
            .width(60)
            TableColumn("Language") { row in Text((row.r.languages ?? []).compactMap(\.name).joined(separator: ", ")).lineLimit(1) }.width(min: 60, ideal: 80)
            TableColumn("Quality", value: \.quality) { row in Pill(text: row.quality, color: .indigo) }.width(min: 80, ideal: 110)
            TableColumn("Score", value: \.score) { row in
                Text(row.score == 0 ? "" : (row.score > 0 ? "+\(row.score)" : "\(row.score)"))
                    .foregroundStyle(row.score >= 0 ? .green : .red).monospacedDigit()
            }.width(45)
            TableColumn("") { row in
                HStack(spacing: 6) {
                    if row.r.rejected == true {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            .help((row.r.rejections ?? []).joined(separator: "\n"))
                    }
                    if grabbing.contains(row.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { attemptGrab(row.r) } label: { Image(systemName: "arrow.down.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Download")
                    }
                }
            }
            .width(50)
        }
        .contextMenu(forSelectionType: ReleaseRow.ID.self) { ids in
            if let id = ids.first, let r = releases.first(where: { $0.id == id }) {
                Button("Download") { attemptGrab(r) }
                if let info = r.infoUrl, let u = URL(string: info) { Link("Open Indexer Page", destination: u) }
                Button("Copy Title") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.title, forType: .string) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let r = releases.first(where: { $0.id == id }) { attemptGrab(r) }
        }
    }

    private func reload() async {
        state = .loading
        do {
            releases = try await load()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func attemptGrab(_ r: ArrRelease) {
        if r.rejected == true { confirmRejected = r } else { doGrab(r) }
    }

    private func doGrab(_ r: ArrRelease) {
        grabbing.insert(r.id)
        Task {
            do {
                try await grab(r)
                app.flash("Sent “\(r.title)” to download client")
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            grabbing.remove(r.id)
        }
    }
}

/// Media info + file metadata block.
struct MediaFileView: View {
    var path: String?
    var size: Int64?
    var quality: ArrQuality?
    var languages: [ArrLanguage]?
    var mediaInfo: ArrMediaInfo?
    var releaseGroup: String?
    var added: Date?
    var customFormatScore: Int?
    var cutoffNotMet: Bool?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((path as NSString?)?.lastPathComponent ?? "File")
                        .font(.callout.weight(.medium)).textSelection(.enabled).lineLimit(2)
                    if let path { Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1) }
                }
                Spacer()
                if let onDelete {
                    Button(role: .destructive, action: onDelete) { Label("Delete File", systemImage: "trash") }
                        .buttonStyle(.glass)
                }
            }
            FlowLayout(spacing: 6) {
                Pill(text: quality?.name ?? "Unknown", color: cutoffNotMet == true ? .orange : .indigo, symbol: "sparkles.tv")
                Pill(text: Fmt.bytes(size), color: .secondary, symbol: "internaldrive")
                if let r = mediaInfo?.resolution { Pill(text: r, color: .blue) }
                if let v = mediaInfo?.videoCodec, !v.isEmpty { Pill(text: v, color: .teal, symbol: "film") }
                if let dr = mediaInfo?.videoDynamicRangeType, !dr.isEmpty { Pill(text: dr, color: .purple) }
                if let a = mediaInfo?.audioCodec, !a.isEmpty {
                    Pill(text: "\(a) \(mediaInfo?.audioChannels.map { String(format: "%.1f", $0) } ?? "")", color: .pink, symbol: "speaker.wave.2")
                }
                if let l = mediaInfo?.audioLanguages, !l.isEmpty { Pill(text: l, color: .secondary, symbol: "globe") }
                if let s = mediaInfo?.subtitles, !s.isEmpty { Pill(text: s, color: .secondary, symbol: "captions.bubble") }
                if let rg = releaseGroup, !rg.isEmpty { Pill(text: rg, color: .secondary, symbol: "person.3") }
                if let sc = customFormatScore, sc != 0 { Pill(text: "CF \(sc)", color: sc > 0 ? .green : .red) }
                if let added { Pill(text: Fmt.date(added), color: .secondary, symbol: "calendar") }
            }
        }
    }
}

struct HistoryRow: View {
    var record: ArrHistoryRecord
    var showsMedia = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                if showsMedia, let title = mediaTitle {
                    Text(title).font(.callout.weight(.medium)).lineLimit(1)
                }
                Text(record.sourceTitle ?? record.eventLabel).font(showsMedia ? .caption : .callout).lineLimit(1)
                    .foregroundStyle(showsMedia ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(record.eventLabel).foregroundStyle(color)
                    if let q = record.quality?.name { Text("· \(q)") }
                    if let indexer = record.dataValue("indexer"), !indexer.isEmpty { Text("· \(indexer)") }
                    if let client = record.dataValue("downloadClientName") ?? record.dataValue("downloadClient"), !client.isEmpty { Text("· \(client)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.relative(record.date)).font(.caption).foregroundStyle(.secondary)
                .help(Fmt.dateTime(record.date))
        }
        .padding(.vertical, 3)
    }

    private var mediaTitle: String? {
        if let m = record.movie { return m.title }
        if let s = record.series {
            if let e = record.episode { return "\(s.title) · \(e.code)" }
            return s.title
        }
        return nil
    }

    private var symbol: String {
        switch record.eventType {
        case "grabbed": "arrow.down.circle"
        case "downloadFolderImported", "movieFolderImported", "seriesFolderImported": "checkmark.circle.fill"
        case "downloadFailed": "xmark.circle.fill"
        case "movieFileDeleted", "episodeFileDeleted": "trash"
        case "movieFileRenamed", "episodeFileRenamed": "pencil"
        case "downloadIgnored": "eye.slash"
        default: "clock"
        }
    }
    private var color: Color {
        switch record.eventType {
        case "grabbed": .blue
        case "downloadFolderImported", "movieFolderImported", "seriesFolderImported": .green
        case "downloadFailed": .red
        case "movieFileDeleted", "episodeFileDeleted": .orange
        default: .secondary
        }
    }
}

/// Delete confirmation with options common to Radarr/Sonarr.
struct DeleteMediaSheet: View {
    var title: String
    var exclusionLabel: String
    var onDelete: (_ deleteFiles: Bool, _ addExclusion: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.deleteFilesDefault) private var deleteFiles = false
    @State private var addExclusion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Delete “\(title)”?", systemImage: "trash").font(.title3.bold())
            Toggle("Delete files from disk", isOn: $deleteFiles)
            Toggle(exclusionLabel, isOn: $addExclusion)
            if deleteFiles {
                Label("Files will be permanently removed from the server.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    onDelete(deleteFiles, addExclusion)
                    dismiss()
                }
                .buttonStyle(.glassProminent).tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

/// Multi-select tag picker for *arr tags.
struct TagPicker: View {
    var all: [ArrTag]
    @Binding var selected: Set<Int>
    var create: ((String) async -> ArrTag?)?
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(all) { tag in
                    let on = selected.contains(tag.id)
                    Button {
                        if on { selected.remove(tag.id) } else { selected.insert(tag.id) }
                    } label: {
                        Label(tag.label, systemImage: on ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.glass)
                    .tint(on ? .accentColor : nil)
                    .controlSize(.small)
                }
            }
            if let create {
                HStack {
                    TextField("New tag", text: $newTag).textFieldStyle(.roundedBorder).frame(width: 160)
                    Button("Add") {
                        let label = newTag.trimmingCharacters(in: .whitespaces).lowercased()
                        guard !label.isEmpty else { return }
                        Task {
                            if let t = await create(label) { selected.insert(t.id) }
                            newTag = ""
                        }
                    }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Opens a URL in the default browser.
func openWeb(_ s: String?) {
    guard let s, let url = URL(string: s) else { return }
    NSWorkspace.shared.open(url)
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
