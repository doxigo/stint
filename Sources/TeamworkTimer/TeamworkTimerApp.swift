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
            if UserDefaults.standard.bool(forKey: "miniTimer") { MiniTimer.setShown(true, store: store) }
        }
    }

    var body: some Scene {
        Window("Stint", id: "main") {
            MainWindow().environment(store).tint(Brand.purple).id(store.sessionID)
        }
        .defaultSize(width: 920, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .commands { AppCommands(store: store) }
    }
}

/// The status item is the app's main surface, so it keeps running with no window open. (SwiftUI quits
/// an app whose only scene is a Window once that window, or the popover, closes.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
            Button("Mini Timer") {
                MiniTimer.setShown(!MiniTimer.isShown, store: store)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
        }
    }
}
