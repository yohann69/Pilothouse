import SwiftUI
import PilothouseKit

/// Edits qBittorrent's own preferences (the "Options" dialog of the desktop app).
struct QBPreferencesSheet: View {
    let store: TorrentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var prefs: [String: JSONValue] = [:]
    @State private var original: [String: JSONValue] = [:]
    @State private var page = Page.downloads
    @State private var error: String?
    @State private var saving = false

    enum Page: String, CaseIterable, Identifiable {
        case downloads, connection, speed, bittorrent, queueing
        var id: String { rawValue }
        var label: String {
            switch self { case .downloads: "Downloads"; case .connection: "Connection"; case .speed: "Speed"; case .bittorrent: "BitTorrent"; case .queueing: "Queueing & Seeding" }
        }
        var symbol: String {
            switch self { case .downloads: "arrow.down.circle"; case .connection: "network"; case .speed: "speedometer"; case .bittorrent: "point.3.connected.trianglepath.dotted"; case .queueing: "list.number" }
        }
    }

    private var changed: [String: JSONValue] { prefs.filter { original[$0.key] != $0.value } }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: Binding(get: { page }, set: { if let p = $0 { page = p } })) { p in
                Label(p.label, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                if let error { ErrorView(message: error) { Task { await load() } } }
                else if prefs.isEmpty { LoadingView() }
                else { form }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(changed.isEmpty ? "No changes" : "\(changed.count) change\(changed.count == 1 ? "" : "s")").foregroundStyle(.secondary).font(.callout)
                    Spacer()
                    Button("Revert") { prefs = original }.disabled(changed.isEmpty)
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save") { save() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(changed.isEmpty || saving)
                }
                .padding(12)
                .background(.bar)
            }
        }
        .frame(width: 780, height: 580)
        .task { await load() }
    }

    @ViewBuilder
    private var form: some View {
        Form {
            switch page {
            case .downloads:
                SwiftUI.Section("Saving") {
                    text("Default save path", "save_path")
                    toggle("Keep incomplete torrents in", "temp_path_enabled")
                    if bool("temp_path_enabled") { text("Incomplete path", "temp_path") }
                    toggle("Append .!qB to incomplete files", "incomplete_files_ext")
                    toggle("Pre-allocate disk space for all files", "preallocate_all")
                }
                SwiftUI.Section("When adding a torrent") {
                    picker("Content layout", "torrent_content_layout", [("Original", "Original"), ("Create subfolder", "Subfolder"), ("Don't create subfolder", "NoSubfolder")])
                    toggle("Do not start the download automatically", prefs["add_stopped_enabled"] != nil ? "add_stopped_enabled" : "start_paused_enabled")
                    toggle("Automatic torrent management by default", "auto_tmm_enabled")
                    toggle("Delete .torrent files afterwards", "auto_delete_mode", asIntFlag: true)
                }
            case .connection:
                SwiftUI.Section("Listening port") {
                    number("Port for incoming connections", "listen_port")
                    toggle("Use UPnP / NAT-PMP port forwarding", "upnp")
                }
                SwiftUI.Section("Connection limits") {
                    number("Global maximum connections", "max_connec")
                    number("Maximum connections per torrent", "max_connec_per_torrent")
                    number("Global maximum upload slots", "max_uploads")
                    number("Upload slots per torrent", "max_uploads_per_torrent")
                }
            case .speed:
                SwiftUI.Section("Global rate limits (KiB/s, 0 = unlimited)") {
                    kib("Upload", "up_limit")
                    kib("Download", "dl_limit")
                }
                SwiftUI.Section("Alternative rate limits (KiB/s)") {
                    kib("Upload", "alt_up_limit")
                    kib("Download", "alt_dl_limit")
                    toggle("Schedule the use of alternative limits", "scheduler_enabled")
                    if bool("scheduler_enabled") {
                        HStack {
                            Text("From")
                            number(nil, "schedule_from_hour").frame(width: 60); Text(":")
                            number(nil, "schedule_from_min").frame(width: 60)
                            Text("to")
                            number(nil, "schedule_to_hour").frame(width: 60); Text(":")
                            number(nil, "schedule_to_min").frame(width: 60)
                        }
                        picker("Days", "scheduler_days", [("Every day", 0), ("Weekdays", 1), ("Weekends", 2), ("Monday", 3), ("Tuesday", 4), ("Wednesday", 5), ("Thursday", 6), ("Friday", 7), ("Saturday", 8), ("Sunday", 9)])
                    }
                }
                SwiftUI.Section("Settings") {
                    toggle("Apply rate limits to peers on the LAN", "limit_lan_peers")
                    toggle("Apply rate limits to transport overhead", "limit_tcp_overhead")
                    toggle("Apply rate limits to µTP protocol", "limit_utp_rate")
                }
            case .bittorrent:
                SwiftUI.Section("Privacy") {
                    toggle("Enable DHT (decentralized network)", "dht")
                    toggle("Enable Peer Exchange (PeX)", "pex")
                    toggle("Enable Local Peer Discovery", "lsd")
                    picker("Encryption", "encryption", [("Allow encryption", 0), ("Require encryption", 1), ("Disable encryption", 2)])
                    toggle("Enable anonymous mode", "anonymous_mode")
                }
            case .queueing:
                SwiftUI.Section("Torrent queueing") {
                    toggle("Enable torrent queueing", "queueing_enabled")
                    if bool("queueing_enabled") {
                        number("Maximum active downloads", "max_active_downloads")
                        number("Maximum active uploads", "max_active_uploads")
                        number("Maximum active torrents", "max_active_torrents")
                        toggle("Do not count slow torrents in these limits", "dont_count_slow_torrents")
                    }
                }
                SwiftUI.Section("Seeding limits") {
                    toggle("When ratio reaches", "max_ratio_enabled")
                    if bool("max_ratio_enabled") { decimal("Ratio", "max_ratio") }
                    toggle("When total seeding time reaches", "max_seeding_time_enabled")
                    if bool("max_seeding_time_enabled") { number("Minutes", "max_seeding_time") }
                    picker("Then", "max_ratio_act", [("Stop torrent", 0), ("Remove torrent", 1), ("Remove torrent and its files", 3), ("Enable super seeding", 2)])
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Field builders (only shown when the server knows the key)

    private func bool(_ k: String) -> Bool { prefs[k]?.boolValue ?? false }

    @ViewBuilder private func toggle(_ title: String, _ k: String, asIntFlag: Bool = false) -> some View {
        if prefs[k] != nil {
            Toggle(title, isOn: Binding(
                get: { asIntFlag ? (prefs[k]?.intValue ?? 0) != 0 : bool(k) },
                set: { prefs[k] = asIntFlag ? JSONValue($0 ? 1 : 0) : .bool($0) }))
        }
    }

    @ViewBuilder private func text(_ title: String, _ k: String) -> some View {
        if prefs[k] != nil {
            TextField(title, text: Binding(get: { prefs[k]?.stringValue ?? "" }, set: { prefs[k] = .string($0) }))
        }
    }

    @ViewBuilder private func number(_ title: String?, _ k: String) -> some View {
        if prefs[k] != nil {
            let binding = Binding<Int>(get: { prefs[k]?.intValue ?? 0 }, set: { prefs[k] = JSONValue($0) })
            if let title { TextField(title, value: binding, format: .number) } else { TextField("", value: binding, format: .number).labelsHidden() }
        }
    }

    @ViewBuilder private func decimal(_ title: String, _ k: String) -> some View {
        if prefs[k] != nil {
            TextField(title, value: Binding<Double>(get: { prefs[k]?.doubleValue ?? 0 }, set: { prefs[k] = .number($0) }), format: .number)
        }
    }

    /// Value stored in bytes/s, edited in KiB/s.
    @ViewBuilder private func kib(_ title: String, _ k: String) -> some View {
        if prefs[k] != nil {
            TextField(title, value: Binding<Int>(get: { (prefs[k]?.intValue ?? 0) / 1024 }, set: { prefs[k] = JSONValue($0 * 1024) }), format: .number)
        }
    }

    @ViewBuilder private func picker<V: Hashable>(_ title: String, _ k: String, _ options: [(String, V)]) -> some View {
        if prefs[k] != nil {
            Picker(title, selection: Binding<V>(
                get: {
                    let raw = prefs[k]
                    return options.first { opt in
                        if let s = opt.1 as? String { return raw?.stringValue == s }
                        if let i = opt.1 as? Int { return raw?.intValue == i }
                        return false
                    }?.1 ?? options[0].1
                },
                set: { v in
                    if let s = v as? String { prefs[k] = .string(s) } else if let i = v as? Int { prefs[k] = JSONValue(i) }
                })) {
                ForEach(options, id: \.0) { Text($0.0).tag($0.1) }
            }
        }
    }

    private func load() async {
        do {
            let p = try await store.client.preferences().objectValue ?? [:]
            prefs = p
            original = p
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        saving = true
        let delta = changed
        Task {
            do {
                try await store.client.setPreferences(delta)
                await load()
                app.flash("qBittorrent options saved")
                store.refreshNow()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            saving = false
        }
    }
}
