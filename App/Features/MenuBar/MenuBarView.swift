import SwiftUI
import ArrcadeKit

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.menuBarShowsSpeed) private var showSpeed = true

    var body: some View {
        if showSpeed, let t = app.torrents, t.state == .loaded, t.server.dlSpeed + t.server.upSpeed > 0 {
            Text("↓\(compact(t.server.dlSpeed)) ↑\(compact(t.server.upSpeed))").monospacedDigit()
        } else {
            Image(systemName: "arrow.down.circle")
        }
    }

    private func compact(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_048_576 { return String(format: "%.1fM", d / 1_048_576) }
        if d >= 1024 { return String(format: "%.0fK", d / 1024) }
        return "\(v)B"
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = app.torrents {
                HStack(spacing: 10) {
                    StatTile(title: "Download", value: Fmt.speed(t.server.dlSpeed), symbol: "arrow.down.circle.fill", tint: .blue)
                    StatTile(title: "Upload", value: Fmt.speed(t.server.upSpeed), symbol: "arrow.up.circle.fill", tint: .green)
                }
                SpeedSparkline(samples: Array(t.samples.suffix(60))).frame(height: 60)
                let active = t.downloading.sorted { $0.dlspeed > $1.dlspeed }
                if active.isEmpty {
                    Text("No active downloads").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(active.prefix(6)) { tor in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: tor.stateSymbol).foregroundStyle(tor.stateColor)
                                Text(tor.name).font(.caption).lineLimit(1)
                            }
                            HStack {
                                LinearProgress(value: tor.progress, tint: tor.stateColor, height: 4)
                                Text("\(Fmt.percent(tor.progress)) · \(Fmt.eta(tor.eta))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if active.count > 6 { Text("+\(active.count - 6) more").font(.caption).foregroundStyle(.secondary) }
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { t.perform("Resumed all") { try await $0.resume([]) } } label: { Image(systemName: "play.fill") }.help("Resume all")
                        Button { t.perform("Paused all") { try await $0.pause([]) } } label: { Image(systemName: "pause.fill") }.help("Pause all")
                        Button { t.perform { try await $0.toggleAltSpeed() } } label: {
                            Image(systemName: t.server.useAltSpeedLimits ? "tortoise.fill" : "tortoise")
                        }
                        .tint(t.server.useAltSpeedLimits ? .orange : nil)
                        .help("Alternative speed limits")
                        Spacer()
                        Button { open(.torrents); app.showAddTorrent = true } label: { Image(systemName: "plus") }.help("Add torrent")
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Text("qBittorrent isn't configured.").foregroundStyle(.secondary)
            }
            if let s = app.seerr, let pending = s.counts?.pending, pending > 0 {
                Button { open(.requests) } label: {
                    Label("\(pending) request\(pending == 1 ? "" : "s") awaiting approval", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.glass)
                .tint(.orange)
            }
            Divider()
            HStack {
                Button("Open Arrcade") { open(nil) }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { app.torrents?.acquire() }
        .onDisappear { app.torrents?.release() }
    }

    private func open(_ section: Section?) {
        if let section { app.selection = section }
        openWindow(id: "main")
        NSApp.activate()
    }
}
