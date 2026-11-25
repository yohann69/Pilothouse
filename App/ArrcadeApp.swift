import SwiftUI
import ArrcadeKit
import UniformTypeIdentifiers

@main
struct ArrcadeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel.shared
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true

    init() {
        UserDefaults.standard.register(defaults: [
            Prefs.torrentInterval: 1.5,
            Prefs.backgroundInterval: 10.0,
            Prefs.posterSize: PosterSize.medium.rawValue,
            Prefs.notifyTorrentComplete: true,
            Prefs.showMenuBar: true,
            Prefs.menuBarShowsSpeed: true,
            Prefs.calendarDays: 30,
            Prefs.confirmDestructive: true,
            Prefs.showUnmonitoredCalendar: true,
            Prefs.tintedGlass: true
        ])
    }

    var body: some Scene {
        WindowGroup("Arrcade", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 980, minHeight: 620)
                .onOpenURL { app.handle(url: $0) }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .windowToolbarStyle(.unified)
        .commands { AppCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environment(app)
        } label: {
            MenuBarLabel()
                .environment(app)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { AppModel.shared.handle(url: url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: Prefs.notifyTorrentComplete) {
            AppModel.shared.requestNotificationPermission()
        }
        #if DEBUG
        DebugSelfTest.runIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct AppCommands: Commands {
    let app: AppModel
    @FocusedValue(\.refreshAction) private var refresh

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Torrent or Magnet…") {
                app.selection = .torrents
                app.showAddTorrent = true
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(!app.isConfigured(.qbittorrent))
        }
        CommandGroup(after: .toolbar) {
            Button("Refresh") { refresh?() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(refresh == nil)
            Divider()
        }
        CommandMenu("Go") {
            ForEach(Section.allCases) { section in
                if let key = section.shortcut {
                    Button(section.title) { app.selection = section }
                        .keyboardShortcut(key, modifiers: [.command])
                } else {
                    Button(section.title) { app.selection = section }
                }
            }
        }
        CommandMenu("Torrents") {
            Button("Resume All") { app.torrents?.perform("Resumed all") { try await $0.resume([]) } }
            Button("Pause All") { app.torrents?.perform("Paused all") { try await $0.pause([]) } }
            Divider()
            Button("Toggle Alternative Speed Limits") { app.torrents?.perform { try await $0.toggleAltSpeed() } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Focused refresh action

struct RefreshActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var refreshAction: (() -> Void)? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}
