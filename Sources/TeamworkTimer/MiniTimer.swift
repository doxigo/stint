import AppKit
import SwiftUI

/// Floating timer that stays above other windows (and full-screen apps) without taking focus.
/// Replaces the old app's 210×100 compact mode.
@MainActor
enum MiniTimer {
    private static var panel: NSPanel?

    static var isShown: Bool { panel?.isVisible == true }

    static func setShown(_ shown: Bool, store: Store) {
        UserDefaults.standard.set(shown, forKey: "miniTimer")
        guard shown else { panel?.orderOut(nil); return }
        let panel = panel ?? makePanel(store)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private static func makePanel(_ store: Store) -> NSPanel {
        let host = NSHostingView(rootView: MiniTimerView().environment(store).tint(Brand.purple))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        if !panel.setFrameUsingName("MiniTimer"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - host.fittingSize.width - 16, y: screen.maxY - 16))
        }
        panel.setFrameAutosaveName("MiniTimer")
        return panel
    }
}

struct MiniTimerView: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if let timer = store.activeTimer {
                Button { Task { await store.toggle(timer) } } label: {
                    Image(systemName: timer.running ? "pause.fill" : "play.fill").frame(width: 16)
                }
                .accessibilityLabel(timer.running ? "Pause" : "Resume")
                Text(store.title(of: timer)).lineLimit(1)
                Spacer(minLength: 8)
                TimerText(timer: timer).font(.title3.weight(.medium))
            } else {
                Button { Task { await store.resumeLast() } } label: {
                    Image(systemName: "play.fill").frame(width: 16)
                }
                .accessibilityLabel("Resume last timer")
                .disabled(store.recents.isEmpty)
                Text("No timer running").foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            Button { MiniTimer.setShown(false, store: store) } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Hide Mini Timer")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 300)
        .glassEffect(.regular, in: .capsule)
        .padding(6) // room for the shadow inside the borderless panel
    }
}
