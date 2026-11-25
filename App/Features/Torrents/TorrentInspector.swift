import SwiftUI
import ArrcadeKit

struct TorrentInspector: View {
    let store: TorrentStore
    let torrent: QBTorrent
    @State private var tab = Tab.general
    @State private var props: QBProperties?
    @State private var files: [QBFile] = []
    @State private var trackers: [QBTracker] = []
    @State private var peers: [QBPeer] = []
    @State private var fileSelection = Set<Int>()
    @State private var newTrackers = ""
    @State private var renaming: QBFile?
    @State private var newName = ""

    enum Tab: String, CaseIterable, Identifiable {
        case general, files, trackers, peers
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(torrent.name).font(.headline).lineLimit(3).textSelection(.enabled)
                HStack {
                    Label(torrent.stateLabel, systemImage: torrent.stateSymbol).foregroundStyle(torrent.stateColor)
                    Spacer()
                    Text(Fmt.percent(torrent.progress)).monospacedDigit()
                }
                .font(.callout)
                LinearProgress(value: torrent.progress, tint: torrent.stateColor, height: 6)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            store.perform { torrent.isPaused ? try await $0.resume([torrent.hash]) : try await $0.pause([torrent.hash]) }
                        } label: { Image(systemName: torrent.isPaused ? "play.fill" : "pause.fill") }
                            .help(torrent.isPaused ? "Resume" : "Pause")
                        Button { store.perform("Rechecking") { try await $0.recheck([torrent.hash]) } } label: { Image(systemName: "checkmark.arrow.trianglehead.counterclockwise") }
                            .help("Force recheck")
                        Button { store.perform("Reannounced") { try await $0.reannounce([torrent.hash]) } } label: { Image(systemName: "megaphone") }
                            .help("Reannounce")
                        Button { copyToPasteboard(torrent.magnetURI); AppModel.shared.flash("Magnet link copied") } label: { Image(systemName: "link") }
                            .help("Copy magnet link")
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)
            Divider()
            Group {
                switch tab {
                case .general: general
                case .files: filesView
                case .trackers: trackersView
                case .peers: peersView
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: "\(torrent.hash)-\(tab)") { await poll() }
        .sheet(item: $renaming) { f in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename File").font(.headline)
                TextField("Path", text: $newName).textFieldStyle(.roundedBorder).frame(width: 460)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }
                    Button("Rename") {
                        let old = f.name, new = newName, hash = torrent.hash
                        store.perform("Renamed") { try await $0.renameFile(hash, oldPath: old, newPath: new) }
                        renaming = nil
                        Task { try? await Task.sleep(for: .milliseconds(400)); await refresh() }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding()
        }
    }

    private func poll() async {
        await store.client.clearPeers(torrent.hash)
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refresh() async {
        let c = store.client, h = torrent.hash
        switch tab {
        case .general: props = try? await c.properties(h)
        case .files: if let f = try? await c.files(h) { files = f }
        case .trackers: if let t = try? await c.trackers(h) { trackers = t }
        case .peers: if let p = try? await c.peers(h) { peers = p }
        }
    }

    // MARK: General

    private var general: some View {
        Form {
            SwiftUI.Section("Transfer") {
                KeyValueRow(key: "Size", value: "\(torrent.size.byteString) (\(Fmt.bytes(torrent.amountLeft)) left)")
                KeyValueRow(key: "Downloaded", value: Fmt.bytes(props?.total_downloaded ?? torrent.downloaded))
                KeyValueRow(key: "Uploaded", value: Fmt.bytes(props?.total_uploaded ?? torrent.uploaded))
                KeyValueRow(key: "Ratio", value: Fmt.ratio(torrent.ratio))
                KeyValueRow(key: "Down Speed", value: "\(Fmt.speed(torrent.dlspeed))" + (props?.dl_speed_avg.map { " (avg \(Fmt.speed($0)))" } ?? ""))
                KeyValueRow(key: "Up Speed", value: "\(Fmt.speed(torrent.upspeed))" + (props?.up_speed_avg.map { " (avg \(Fmt.speed($0)))" } ?? ""))
                KeyValueRow(key: "ETA", value: torrent.isComplete ? "—" : Fmt.eta(torrent.eta))
                KeyValueRow(key: "Seeds", value: "\(props?.seeds ?? torrent.numSeeds) of \(props?.seeds_total ?? torrent.numComplete)")
                KeyValueRow(key: "Peers", value: "\(props?.peers ?? torrent.numLeechs) of \(props?.peers_total ?? torrent.numIncomplete)")
                KeyValueRow(key: "Connections", value: "\(props?.nb_connections ?? 0) / \(props?.nb_connections_limit ?? 0)")
                KeyValueRow(key: "Wasted", value: Fmt.bytes(props?.total_wasted))
                KeyValueRow(key: "Availability", value: torrent.availability < 0 ? "—" : String(format: "%.3f", torrent.availability))
                KeyValueRow(key: "Time Active", value: Fmt.duration(props?.time_elapsed ?? torrent.timeActive))
                KeyValueRow(key: "Seeding Time", value: Fmt.duration(props?.seeding_time ?? torrent.seedingTime))
                KeyValueRow(key: "Limits", value: "↓ \(torrent.dlLimit > 0 ? Fmt.speed(torrent.dlLimit) : "∞")  ↑ \(torrent.upLimit > 0 ? Fmt.speed(torrent.upLimit) : "∞")")
            }
            SwiftUI.Section("Information") {
                KeyValueRow(key: "Category", value: torrent.category.nilIfEmpty ?? "—")
                KeyValueRow(key: "Tags", value: torrent.tagsLabel.nilIfEmpty ?? "—")
                KeyValueRow(key: "Save Path", value: props?.save_path ?? torrent.savePath)
                KeyValueRow(key: "Added", value: Fmt.dateTime(torrent.addedOn))
                KeyValueRow(key: "Completed", value: Fmt.dateTime(torrent.completionOn))
                if let p = props {
                    KeyValueRow(key: "Pieces", value: "\(p.pieces_num ?? 0) × \(Fmt.bytes(p.piece_size)) (have \(p.pieces_have ?? 0))")
                    KeyValueRow(key: "Private", value: p.isPrivate == true ? "Yes" : "No")
                    if let c = p.comment, !c.isEmpty { KeyValueRow(key: "Comment", value: c) }
                    if let c = p.created_by, !c.isEmpty { KeyValueRow(key: "Created By", value: c) }
                    if let d = p.creation_date, d > 0 { KeyValueRow(key: "Created", value: Fmt.dateTime(Date(timeIntervalSince1970: d))) }
                    if let r = p.reannounce { KeyValueRow(key: "Next Announce", value: Fmt.eta(r)) }
                }
                KeyValueRow(key: "Hash", value: torrent.hash)
                KeyValueRow(key: "Tracker", value: torrent.tracker.nilIfEmpty ?? "—")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Files

    private var filesView: some View {
        VStack(spacing: 0) {
            List(files, selection: $fileSelection) { f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: f.priority == 0 ? "xmark.circle" : "doc")
                            .foregroundStyle(f.priority == 0 ? Color.secondary : (f.priority >= 6 ? .orange : .accentColor))
                        Text((f.name as NSString).lastPathComponent).lineLimit(2).help(f.name)
                            .foregroundStyle(f.priority == 0 ? .secondary : .primary)
                    }
                    HStack {
                        LinearProgress(value: f.progress, tint: f.progress >= 1 ? .green : .blue, height: 4)
                        Text("\(Fmt.percent(f.progress)) of \(f.size.byteString)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(f.priorityLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .tag(f.id)
                .padding(.vertical, 2)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                let list = Array(ids)
                Button("Download (Normal)") { setPriority(list, 1) }
                Button("High Priority") { setPriority(list, 6) }
                Button("Maximum Priority") { setPriority(list, 7) }
                Button("Do Not Download") { setPriority(list, 0) }
                if list.count == 1, let f = files.first(where: { $0.id == list[0] }) {
                    Divider()
                    Button("Rename…") { newName = f.name; renaming = f }
                }
            }
            Divider()
            HStack {
                Text("\(files.count) files · \(files.filter { $0.priority > 0 }.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Priority") {
                    Button("Download All") { setPriority(files.map(\.id), 1) }
                    Button("Skip Selected") { setPriority(Array(fileSelection), 0) }.disabled(fileSelection.isEmpty)
                    Button("Download Selected") { setPriority(Array(fileSelection), 1) }.disabled(fileSelection.isEmpty)
                    Button("High Priority Selected") { setPriority(Array(fileSelection), 6) }.disabled(fileSelection.isEmpty)
                }
                .fixedSize()
            }
            .padding(8)
        }
    }

    private func setPriority(_ ids: [Int], _ p: Int) {
        guard !ids.isEmpty else { return }
        let h = torrent.hash
        store.perform { try await $0.setFilePriority(h, ids: ids, priority: p) }
        Task { try? await Task.sleep(for: .milliseconds(300)); await refresh() }
    }

    // MARK: Trackers

    private var trackersView: some View {
        VStack(spacing: 0) {
            List(trackers) { t in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        StatusDot(color: t.status == 2 ? .green : t.status == 4 ? .red : t.status == 0 ? .gray : .orange)
                        Text(t.url).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    HStack(spacing: 10) {
                        Text(t.statusLabel)
                        if !t.isPseudo {
                            Text("Seeds \(max(0, t.num_seeds ?? 0))")
                            Text("Peers \(max(0, t.num_peers ?? 0))")
                            Text("Leeches \(max(0, t.num_leeches ?? 0))")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if let m = t.msg, !m.isEmpty { Text(m).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                }
                .contextMenu {
                    if !t.isPseudo {
                        Button("Copy URL") { copyToPasteboard(t.url) }
                        Button("Remove Tracker", role: .destructive) {
                            let h = torrent.hash
                            store.perform("Tracker removed") { try await $0.removeTrackers(h, urls: [t.url]) }
                            Task { try? await Task.sleep(for: .milliseconds(300)); await refresh() }
                        }
                    }
                }
            }
            Divider()
            HStack {
                TextField("Add tracker URL(s)", text: $newTrackers).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let urls = newTrackers.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let h = torrent.hash
                    store.perform("Tracker added") { try await $0.addTrackers(h, urls: urls) }
                    newTrackers = ""
                    Task { try? await Task.sleep(for: .milliseconds(300)); await refresh() }
                }
                .disabled(newTrackers.isEmpty)
            }
            .padding(8)
        }
    }

    // MARK: Peers

    private var peersView: some View {
        List(peers) { p in
            HStack(spacing: 8) {
                Text(flag(p.countryCode)).help(p.country)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(p.ip):\(p.port)").font(.callout.monospaced()).textSelection(.enabled)
                    Text("\(p.client) · \(p.connection) · \(p.flags)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.percent(p.progress)).font(.caption.monospacedDigit())
                    HStack(spacing: 6) {
                        if p.dlSpeed > 0 { Text("↓\(Fmt.speed(p.dlSpeed))").foregroundStyle(.blue) }
                        if p.upSpeed > 0 { Text("↑\(Fmt.speed(p.upSpeed))").foregroundStyle(.green) }
                    }
                    .font(.caption2.monospacedDigit())
                }
            }
        }
        .overlay { if peers.isEmpty { ContentUnavailableView("No Peers", systemImage: "person.2.slash") } }
    }

    private func flag(_ code: String) -> String {
        guard code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }
}
