import SwiftUI
import PilothouseKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.sidebarHidden) private var hidden = StoredList<Section>([])
    @AppStorage(Prefs.sidebarOrder) private var order = StoredList<Section>(Section.allCases)
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var visibleSections: [Section] {
        let ordered = order.items + Section.allCases.filter { !order.items.contains($0) }
        return ordered.filter { !hidden.items.contains($0) && app.isAvailable($0) }
    }

    private var groups: [(String, [Section])] {
        var out: [(String, [Section])] = []
        for s in visibleSections {
            if let i = out.firstIndex(where: { $0.0 == s.group }) { out[i].1.append(s) } else { out.append((s.group, [s])) }
        }
        return out
    }

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $app.selection) {
                ForEach(groups, id: \.0) { group in
                    SwiftUI.Section(group.0) {
                        ForEach(group.1) { section in
                            Label(section.title, systemImage: section.symbol)
                                .badge(badge(for: section))
                                .tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            Group {
                if !app.hasAnyService {
                    WelcomeView()
                } else {
                    let section = app.selection ?? .dashboard
                    detail(for: section)
                        .id("\(section.rawValue)-\(section.requires.first.flatMap { app.activeID($0)?.uuidString } ?? "")")
                        .toolbar {
                            if let kind = section.requires.first, app.instances(kind).count > 1 {
                                ToolbarItem(placement: .navigation) { InstancePicker(kind: kind) }
                            }
                        }
                }
            }
            .overlay(alignment: .bottom) { ToastOverlay() }
        }
        .sheet(isPresented: $app.showAddTorrent) {
            if let store = app.torrents {
                AddTorrentSheet(store: store, initialMagnet: app.pendingMagnet, initialFiles: app.pendingTorrentFiles)
                    .onDisappear {
                        app.pendingMagnet = nil
                        app.pendingTorrentFiles = []
                    }
            } else {
                NotConfiguredView(service: .qbittorrent).frame(width: 420, height: 300)
            }
        }
        .task {
            if let seerr = app.seerr { await seerr.loadBasics() }
        }
        .onChange(of: visibleSections) { _, new in
            if let sel = app.selection, !new.contains(sel) { app.selection = new.first }
        }
    }

    private func badge(for section: Section) -> Int {
        switch section {
        case .requests: app.seerr?.counts?.pending ?? 0
        case .torrents: app.torrents?.downloading.count ?? 0
        default: 0
        }
    }

    @ViewBuilder
    private func detail(for section: Section) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .calendar: CalendarView()
        case .activity: ActivityView()
        case .movies:
            if let s = app.radarr { MoviesView(store: s) } else { NotConfiguredView(service: .radarr) }
        case .series:
            if let s = app.sonarr { SeriesListView(store: s) } else { NotConfiguredView(service: .sonarr) }
        case .discover:
            if let s = app.seerr { DiscoverView(store: s) } else { NotConfiguredView(service: .seerr) }
        case .requests:
            if let s = app.seerr { RequestsView(store: s) } else { NotConfiguredView(service: .seerr) }
        case .issues:
            if let s = app.seerr { IssuesView(store: s) } else { NotConfiguredView(service: .seerr) }
        case .torrents:
            if let s = app.torrents { TorrentsView(store: s) } else { NotConfiguredView(service: .qbittorrent) }
        case .search:
            if let s = app.prowlarr { IndexerSearchView(store: s) } else { NotConfiguredView(service: .prowlarr) }
        case .indexers:
            if let s = app.prowlarr { IndexersView(store: s) } else { NotConfiguredView(service: .prowlarr) }
        case .system: SystemView()
        }
    }
}

/// Live transfer summary pinned to the bottom of the sidebar.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let t = app.torrents, t.state == .loaded {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(Fmt.speed(t.server.dlSpeed), systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                    Spacer()
                    Label(Fmt.speed(t.server.upSpeed), systemImage: "arrow.up")
                        .foregroundStyle(.green)
                }
                .font(.caption.monospacedDigit().weight(.medium))
                .contentTransition(.numericText())
                if t.server.useAltSpeedLimits {
                    Label("Alternative speed limits on", systemImage: "tortoise.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(10)
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(26)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .circle)
            Text("Welcome to Pilothouse").font(.largeTitle.bold())
            Text("Control Radarr, Sonarr, Seerr, Prowlarr and qBittorrent from one native Mac app.\nImport your nzb360 Android backup or add servers manually.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ImportBackupButton()
                        .buttonStyle(.glassProminent)
                    SettingsLink { Label("Add Servers…", systemImage: "server.rack") }
                        .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// Switches which server a section shows when several are configured.
struct InstancePicker: View {
    let kind: ServiceKind
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            ForEach(app.instances(kind)) { c in
                Button {
                    app.setActive(kind, c.id)
                } label: {
                    if app.activeID(kind) == c.id { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
            Divider()
            SettingsLink { Text("Manage Connections…") }
        } label: {
            Label(app.config(kind)?.name ?? kind.displayName, systemImage: kind.symbol)
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Choose which \(kind.displayName) server to show")
    }
}
