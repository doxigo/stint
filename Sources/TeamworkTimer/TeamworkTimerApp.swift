import SwiftUI

@main
struct TeamworkTimerApp: App {
    @State private var store: Store

    init() {
        let store = Store()
        _store = State(initialValue: store)
        HotKey.apply(HotKey.saved) { Task { await store.pauseOrResume() } }
        if UserDefaults.standard.bool(forKey: "miniTimer") {
            Task { MiniTimer.setShown(true, store: store) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Teamwork Timer", id: "main") {
            MainWindow().environment(store).tint(Brand.purple)
        }
        .defaultSize(width: 920, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView().environment(store).tint(Brand.purple)
        }
    }
}

/// Menu bar commands; each calls the same Store action as its button.
struct AppCommands: Commands {
    let store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
            ForEach(Array(Store.Section.allCases.enumerated()), id: \.element) { index, section in
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
