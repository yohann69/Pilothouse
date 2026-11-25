import SwiftUI
import ArrcadeKit
import UniformTypeIdentifiers

/// Sheets for torrent actions that need input.
struct TorrentActionSheet: View {
    let store: TorrentStore
    let action: TorrentAction
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.deleteFilesDefault) private var deleteFilesDefault = false
    @State private var deleteFiles = false
    @State private var text = ""
    @State private var dl = 0.0
    @State private var ul = 0.0
    @State private var ratioMode = 0      // 0 global, 1 unlimited, 2 custom
    @State private var ratio = 2.0
    @State private var timeMode = 0
    @State private var minutes = 1440.0
    @State private var tagSelection = Set<String>()

    private var torrents: [QBTorrent] {
        let hashes = hashes
        return store.torrents.filter { hashes.contains($0.hash) }
    }
    private var hashes: [String] {
        switch action {
        case .delete(let h), .location(let h), .limits(let h), .share(let h), .newCategory(let h), .tags(let h): h
        case .rename(let t): [t.hash]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirmLabel, role: isDestructive ? .destructive : nil) { apply(); dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(isDestructive ? .red : nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear(perform: setup)
    }

    private var isDestructive: Bool { if case .delete = action { return true }; return false }

    private var confirmLabel: String {
        switch action {
        case .delete: "Delete"
        case .location: "Move"
        case .rename: "Rename"
        case .newCategory: "Create"
        default: "Apply"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch action {
        case .delete:
            Label(torrents.count == 1 ? "Delete “\(torrents.first?.name ?? "")”?" : "Delete \(torrents.count) torrents?", systemImage: "trash")
                .font(.title3.bold()).lineLimit(3)
            Toggle("Also delete downloaded files", isOn: $deleteFiles)
            if deleteFiles {
                Label("Files will be permanently removed from disk.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        case .location:
            Text("Set Location").font(.title3.bold())
            TextField("Save path", text: $text).textFieldStyle(.roundedBorder)
            Text("Moves data for \(torrents.count) torrent(s) on the server.").font(.caption).foregroundStyle(.secondary)
        case .rename:
            Text("Rename Torrent").font(.title3.bold())
            TextField("Name", text: $text).textFieldStyle(.roundedBorder)
        case .newCategory:
            Text("New Category").font(.title3.bold())
            TextField("Name", text: $text).textFieldStyle(.roundedBorder)
        case .tags:
            Text("Tags").font(.title3.bold())
            FlowLayout(spacing: 6) {
                ForEach(store.tags, id: \.self) { tag in
                    let on = tagSelection.contains(tag)
                    Button { if on { tagSelection.remove(tag) } else { tagSelection.insert(tag) } } label: {
                        Label(tag, systemImage: on ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
            }
            TextField("New tags (comma separated)", text: $text).textFieldStyle(.roundedBorder)
        case .limits:
            Text("Speed Limits").font(.title3.bold())
            LimitField(title: "Download", kib: $dl)
            LimitField(title: "Upload", kib: $ul)
            Text("0 = unlimited").font(.caption).foregroundStyle(.secondary)
        case .share:
            Text("Share Limits").font(.title3.bold())
            Picker("Ratio", selection: $ratioMode) { Text("Global").tag(0); Text("Unlimited").tag(1); Text("Custom").tag(2) }
            if ratioMode == 2 { TextField("Ratio", value: $ratio, format: .number).textFieldStyle(.roundedBorder) }
            Picker("Seeding Time", selection: $timeMode) { Text("Global").tag(0); Text("Unlimited").tag(1); Text("Custom").tag(2) }
            if timeMode == 2 { TextField("Minutes", value: $minutes, format: .number).textFieldStyle(.roundedBorder) }
        }
    }

    private func setup() {
        switch action {
        case .delete: deleteFiles = deleteFilesDefault
        case .location: text = torrents.first?.savePath ?? ""
        case .rename(let t): text = t.name
        case .limits:
            dl = Double((torrents.first?.dlLimit ?? 0) / 1024)
            ul = Double((torrents.first?.upLimit ?? 0) / 1024)
        case .tags:
            tagSelection = Set(store.tags.filter { tag in torrents.allSatisfy { $0.tags.contains(tag) } })
        default: break
        }
    }

    private func apply() {
        let h = hashes
        switch action {
        case .delete:
            let files = deleteFiles
            store.perform(files ? "Deleted with files" : "Removed") { try await $0.delete(h, deleteFiles: files) }
        case .location:
            let loc = text
            store.perform("Moving to \(loc)") { try await $0.setLocation(h, loc) }
        case .rename(let t):
            let name = text
            store.perform("Renamed") { try await $0.rename(t.hash, name) }
        case .newCategory:
            let name = text.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            store.perform("Category \(name) set") {
                try? await $0.createCategory(name, savePath: "")
                try await $0.setCategory(h, name)
            }
        case .tags:
            let newTags = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let add = Array(tagSelection) + newTags
            let remove = store.tags.filter { !tagSelection.contains($0) }
            store.perform("Tags updated") {
                if !remove.isEmpty { try await $0.removeTags(h, remove) }
                if !add.isEmpty { try await $0.addTags(h, add) }
            }
        case .limits:
            let d = Int(dl * 1024), u = Int(ul * 1024)
            store.perform("Limits set") {
                try await $0.setDownloadLimit(h, d)
                try await $0.setUploadLimit(h, u)
            }
        case .share:
            let r = ratioMode == 0 ? -2 : ratioMode == 1 ? -1 : ratio
            let m = timeMode == 0 ? -2 : timeMode == 1 ? -1 : Int(minutes)
            store.perform("Share limits set") { try await $0.setShareLimits(h, ratio: r, seedingMinutes: m) }
        }
    }
}

struct LimitField: View {
    var title: String
    @Binding var kib: Double
    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            TextField("0", value: $kib, format: .number).textFieldStyle(.roundedBorder).frame(width: 110)
            Text("KiB/s").foregroundStyle(.secondary)
            Spacer()
            Menu("Presets") {
                ForEach([0, 512, 1024, 2048, 5120, 10240, 25600, 51200], id: \.self) { v in
                    Button(v == 0 ? "Unlimited" : Int64(v * 1024).byteString + "/s") { kib = Double(v) }
                }
            }
            .fixedSize()
        }
    }
}

struct SpeedLimitsPopover: View {
    let store: TorrentStore
    @State private var dl = 0.0
    @State private var ul = 0.0
    @State private var altDl = 0.0
    @State private var altUl = 0.0
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Global Speed Limits").font(.headline)
            LimitField(title: "Download", kib: $dl)
            LimitField(title: "Upload", kib: $ul)
            Divider()
            Toggle("Alternative speed limits", isOn: Binding(get: { store.server.useAltSpeedLimits }, set: { _ in store.perform { try await $0.toggleAltSpeed() } }))
                .toggleStyle(.switch)
            LimitField(title: "Alt. Down", kib: $altDl)
            LimitField(title: "Alt. Up", kib: $altUl)
            HStack {
                Text("0 = unlimited").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { apply() }.buttonStyle(.glassProminent).disabled(!loaded)
            }
        }
        .padding()
        .frame(width: 440)
        .task {
            if let prefs = try? await store.client.preferences() {
                dl = Double((prefs["dl_limit"]?.intValue ?? 0) / 1024)
                ul = Double((prefs["up_limit"]?.intValue ?? 0) / 1024)
                altDl = Double((prefs["alt_dl_limit"]?.intValue ?? 0) / 1024)
                altUl = Double((prefs["alt_up_limit"]?.intValue ?? 0) / 1024)
                loaded = true
            }
        }
    }

    private func apply() {
        let p: [String: JSONValue] = [
            "dl_limit": JSONValue(Int(dl * 1024)), "up_limit": JSONValue(Int(ul * 1024)),
            "alt_dl_limit": JSONValue(Int(altDl * 1024)), "alt_up_limit": JSONValue(Int(altUl * 1024))
        ]
        store.perform("Speed limits saved") { try await $0.setPreferences(p) }
    }
}

struct CategoryManagerSheet: View {
    let store: TorrentStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var path = ""
    @State private var editing: QBCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Categories").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            List {
                ForEach(store.categories) { c in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(c.name)
                            Text(c.savePath.nilIfEmpty ?? "Default save path").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(store.torrents.filter { $0.category == c.name }.count)").foregroundStyle(.secondary).monospacedDigit()
                        Button { editing = c; name = c.name; path = c.savePath } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                        Button(role: .destructive) {
                            store.perform("Removed \(c.name)") { try await $0.removeCategories([c.name]) }
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            Divider()
            HStack {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 150).disabled(editing != nil)
                TextField("Save path (optional)", text: $path).textFieldStyle(.roundedBorder)
                if editing != nil {
                    Button("Cancel") { editing = nil; name = ""; path = "" }
                }
                Button(editing == nil ? "Add" : "Save") {
                    let n = name.trimmingCharacters(in: .whitespaces), p = path
                    if editing != nil {
                        store.perform("Updated \(n)") { try await $0.editCategory(n, savePath: p) }
                    } else {
                        store.perform("Created \(n)") { try await $0.createCategory(n, savePath: p) }
                    }
                    editing = nil; name = ""; path = ""
                }
                .buttonStyle(.glassProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 460)
    }
}

/// Add magnets / URLs / .torrent files with full options.
struct AddTorrentSheet: View {
    let store: TorrentStore
    var initialMagnet: String?
    var initialFiles: [URL]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var links = ""
    @State private var files: [URL] = []
    @State private var category = ""
    @State private var tags = Set<String>()
    @State private var savePath = ""
    @State private var defaultPath = ""
    @State private var paused = false
    @State private var skipCheck = false
    @State private var sequential = false
    @State private var firstLast = false
    @State private var autoTMM: Int = 0 // 0 default, 1 on, 2 off
    @State private var layout = "Original"
    @State private var rename = ""
    @State private var dlLimit = 0.0
    @State private var upLimit = 0.0
    @State private var showImporter = false
    @State private var adding = false
    @AppStorage("qbt.lastCategory") private var lastCategory = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Torrents").font(.title2.bold())
                Spacer()
            }
            .padding([.horizontal, .top])
            Form {
                SwiftUI.Section("Sources") {
                    TextEditor(text: $links)
                        .font(.callout.monospaced())
                        .frame(height: 90)
                        .overlay(alignment: .topLeading) {
                            if links.isEmpty {
                                Text("Magnet links or URLs, one per line").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false)
                            }
                        }
                    ForEach(files, id: \.self) { f in
                        HStack {
                            Image(systemName: "doc.fill").foregroundStyle(.tint)
                            Text(f.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button { files.removeAll { $0 == f } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                        }
                    }
                    Button { showImporter = true } label: { Label("Choose .torrent Files…", systemImage: "folder") }
                }
                SwiftUI.Section("Options") {
                    Picker("Category", selection: $category) {
                        Text("None").tag("")
                        ForEach(store.categories) { Text($0.name).tag($0.name) }
                    }
                    if !store.tags.isEmpty {
                        LabeledContent("Tags") {
                            FlowLayout(spacing: 6) {
                                ForEach(store.tags, id: \.self) { t in
                                    let on = tags.contains(t)
                                    Button { if on { tags.remove(t) } else { tags.insert(t) } } label: { Label(t, systemImage: on ? "checkmark.circle.fill" : "circle") }
                                        .buttonStyle(.glass).controlSize(.small)
                                }
                            }
                        }
                    }
                    TextField("Save Path", text: $savePath, prompt: Text(defaultPath.nilIfEmpty ?? "Default"))
                    TextField("Rename", text: $rename, prompt: Text("Keep original name"))
                    Picker("Content Layout", selection: $layout) {
                        Text("Original").tag("Original"); Text("Create Subfolder").tag("Subfolder"); Text("Don't Create Subfolder").tag("NoSubfolder")
                    }
                    Picker("Torrent Management", selection: $autoTMM) {
                        Text("Default").tag(0); Text("Automatic").tag(1); Text("Manual").tag(2)
                    }
                    Toggle("Start paused", isOn: $paused)
                    Toggle("Skip hash check", isOn: $skipCheck)
                    Toggle("Download in sequential order", isOn: $sequential)
                    Toggle("Download first and last pieces first", isOn: $firstLast)
                    LimitField(title: "Down limit", kib: $dlLimit)
                    LimitField(title: "Up limit", kib: $upLimit)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { add() } label: {
                    if adding { ProgressView().controlSize(.small) } else { Label("Add", systemImage: "plus") }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(adding || (parsedLinks.isEmpty && files.isEmpty))
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files += urls.filter { !files.contains($0) } }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in if !files.contains(url) { files.append(url) } }
                }
            }
            return true
        }
        .onAppear {
            links = initialMagnet ?? ""
            files = initialFiles
            category = store.categories.contains { $0.name == lastCategory } ? lastCategory : ""
        }
        .task { defaultPath = (try? await store.client.defaultSavePath()) ?? "" }
    }

    private var parsedLinks: [String] {
        links.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var summary: String {
        let n = parsedLinks.count + files.count
        return n == 0 ? "Nothing to add yet" : "\(n) item\(n == 1 ? "" : "s") to add"
    }

    private func add() {
        adding = true
        lastCategory = category
        var o = QBAddOptions()
        o.savePath = savePath.nilIfEmpty
        o.category = category.nilIfEmpty
        o.tags = Array(tags)
        o.paused = paused
        o.skipChecking = skipCheck
        o.sequential = sequential
        o.firstLastPiece = firstLast
        o.rename = rename.nilIfEmpty
        o.autoTMM = autoTMM == 0 ? nil : autoTMM == 1
        o.contentLayout = layout
        o.dlLimit = dlLimit > 0 ? Int(dlLimit * 1024) : nil
        o.upLimit = upLimit > 0 ? Int(upLimit * 1024) : nil
        let urls = parsedLinks
        let fileURLs = files
        let options = o
        Task {
            do {
                var payload: [(name: String, data: Data)] = []
                for f in fileURLs {
                    let access = f.startAccessingSecurityScopedResource()
                    defer { if access { f.stopAccessingSecurityScopedResource() } }
                    payload.append((f.lastPathComponent, try Data(contentsOf: f)))
                }
                try await store.client.add(urls: urls, torrentFiles: payload, options: options)
                app.flash("Added \(urls.count + payload.count) torrent\(urls.count + payload.count == 1 ? "" : "s")")
                store.refreshNow()
                dismiss()
            } catch {
                app.flash(error.localizedDescription, .error)
            }
            adding = false
        }
    }
}
