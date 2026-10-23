import SwiftUI

@main
struct TeamworkTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: Store

    init() {
        let store = Store()
        _store = State(initialValue: store)
        HotKey.apply(HotKey.saved) { Task { await store.pauseOrResume() } }
        Task {
            StatusItem.install(store)
            Updater.shared.start(store)
        }
    }

    var body: some Scene {
        Window("Stint", id: "main") {
            MainWindow().environment(store).tint(Brand.purple).id(store.sessionID)
        }
        .defaultSize(width: 920, height: 620)
        // Stint lives in the menu bar; `open Stint.app --args -openWindowAtLaunch YES` opens the window too (for test copies).
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "openWindowAtLaunch") ? .presented : .suppressed)
        .commands { AppCommands(store: store) }
    }
}

/// The status item is the app's main surface, so it keeps running with no window open. (SwiftUI quits
/// an app whose only scene is a Window once that window, or the popover, closes.)
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Takes `stint:` URLs as Apple events, ahead of SwiftUI, which would route them to a scene. The sign-in session
    /// catches its own redirect (`AppRedirect`), so a stray one, say from an old browser tab, needs nothing more.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {}
}

/// Menu bar commands; each calls the same Store action as its button.
struct AppCommands: Commands {
    let store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Commands exist from launch, so they hand the store a way to open the main window
        // (used by the end-of-day notification's "Log All…" and the status item's popover).
        let _ = store.openMainWindow = { [openWindow] in openWindow(id: "main") }
        // Settings live in the main window's sidebar rather than a separate window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "main")
                store.section = .settings
            }
            .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("New Timer…") {
                openWindow(id: "main")
                store.showingNewTimer = true
            }
            .keyboardShortcut("n")
            .disabled(!store.isSignedIn)
        }
        CommandMenu("Timer") {
            Button(store.runningTimer == nil ? "Resume Last Timer" : "Pause Timer") {
                Task { await store.pauseOrResume() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!store.isSignedIn)
            Divider()
            Button("Refresh") { Task { await store.refresh() } }
                .keyboardShortcut("r")
                .disabled(!store.isSignedIn)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(Store.Section.library.enumerated()), id: \.element) { index, section in
                Button(section.rawValue) {
                    openWindow(id: "main")
                    store.section = section
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
        }
        CommandGroup(before: .windowArrangement) {
            Button("Main Window") { openWindow(id: "main") }
                .keyboardShortcut("0")
            Divider()
        }
    }
}
