import SwiftUI

/// The status item, the app's main timer display (as in Harvest): live time of the current timer,
/// including one started on the web, or an icon when nothing is tracked. A click opens the popover.
/// Hand-made rather than a MenuBarExtra: macOS handles clicks on a MenuBarExtra item itself and only
/// asks SwiftUI to open its window.
@MainActor final class StatusItem: NSObject, NSPopoverDelegate {
    private static var shared: StatusItem?
    private let store: Store
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    /// One view graph for every open: building a fresh one held the main thread ~60–90 ms per click (measured).
    private lazy var content: NSViewController = {
        let content = NSHostingController(rootView: PopoverRoot().environment(store))
        content.sizingOptions = .preferredContentSize // follows each screen's height
        return content
    }()
    /// Posted just before each open; the reused content goes back to today and reloads.
    static let willOpen = Notification.Name("StatusItem.willOpen")
    /// Event monitors that close the popover while it's open (see `watchOutside`).
    private var monitors: [Any] = []

    static func install(_ store: Store) {
        shared = StatusItem(store: store)
    }

    private init(store: Store) {
        self.store = store
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        // Only this item's own click opens and closes it. A transient popover closed itself on that click's
        // mouse-up, then the click reached the app through MenuBarAgent ~0.3 s later and reopened it (logged).
        popover.behavior = .applicationDefined
        // Content runs under the arrow, so the header's slate fills it and the arrow reads as part of the bar.
        popover.hasFullSizeContent = true
        // Instant, like a menu. While the close animation runs the popover still counts as shown, so
        // a quick second click on the item was lost (measured).
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = content
        content.view.layoutSubtreeIfNeeded() // builds the view graph now rather than on the first click
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // Opening the main window from the popover hands it the focus; the popover steps aside.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let window = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let popover = self?.popover, popover.isShown,
                      window != popover.contentViewController?.view.window.map(ObjectIdentifier.init) else { return }
                popover.performClose(nil)
            }
        }
        track()
    }

    /// Redraws whenever anything it read from the store changes (the store's clock ticks each second
    /// while a timer runs). Settings changes arrive through the defaults notification instead.
    private func track() {
        withObservationTracking { update() } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func update() {
        guard let button = item.button else { return }
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init) ?? .time
        guard let timer = store.activeTimer else {
            return show(Self.symbol("timer"), title: "", label: "Teamwork Timer", in: button)
        }
        let state = timer.running ? "Running" : "Paused"
        // Shape, not just colour, tells running from paused: pause while running, as in Harvest.
        let glyph = Self.symbol(timer.running ? "pause.fill" : "play.fill")
        let highlight = defaults.object(forKey: "menuBarHighlight") as? Bool ?? true
        guard style != .icon else {
            let square = MenuBarBadge.image(running: timer.running, highlight: highlight, text: "")
            return show(square ?? glyph, title: "", label: state, in: button)
        }
        // Plain text on the store's clock; see `Store.menuBarNow`.
        let elapsed = store.elapsed(timer, at: store.menuBarNow)
        let time = defaults.bool(forKey: "menuBarSeconds") ? elapsed.clock : elapsed.hoursMinutes
        let label = "\(state), \(elapsed.spoken)"
        let text = style == .taskAndTime ? "\(Self.shortened(store.title(of: timer)))  \(time)" : time
        if let pill = MenuBarBadge.image(running: timer.running, highlight: highlight, text: text) {
            show(pill, title: "", label: label, in: button)
        } else {
            // Leading space: the button sets its title flush against the image.
            show(glyph, title: " \(text)", label: label, in: button)
        }
    }

    private func show(_ image: NSImage, title: String, label: String, in button: NSStatusBarButton) {
        if button.image !== image { button.image = image }
        if button.title != title {
            button.title = title
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        }
        let position: NSControl.ImagePosition = title.isEmpty ? .imageOnly : .imageLeading
        if button.imagePosition != position { button.imagePosition = position }
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
    }

    @objc private func clicked(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NotificationCenter.default.post(name: Self.willOpen, object: nil)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey() // takes typing even while another app is active
        // Active before the first click lands. macOS declines plain activate() here (the item's click
        // reaches the app through MenuBarAgent), so the popover's first click activated the app instead,
        // and that activation closed the menu the same click had opened (the Open Window chevron).
        // After makeKey, so the popover stays the key window once the app is active.
        NSApp.activate(ignoringOtherApps: true)
        button.highlight(true)
        watchOutside()
    }

    /// While open: a click anywhere outside closes it (other apps, the desktop, other menu bar items, this
    /// app's other windows), and so does Esc. A click on this item is left to `clicked(_:)`, which toggles.
    private func watchOutside() {
        let onItem = { NSApp.windows.contains { $0.level == .statusBar && $0.frame.contains(NSEvent.mouseLocation) } }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { if !onItem() { self?.popover.performClose(nil) } }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            // true: the event closed the popover and goes no further (Esc).
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                // The popover's own window, or one it opened (a date picker's calendar is a child window).
                var window = event.window
                while let shown = window, shown !== self.popover.contentViewController?.view.window { window = shown.parent }
                let inPopover = window != nil
                if event.type == .keyDown {
                    guard inPopover, event.keyCode == 53 else { return false } // Esc
                    self.popover.performClose(nil)
                    return true
                }
                if !inPopover, event.window?.level != .statusBar { self.popover.performClose(nil) }
                return false
            }
            return swallow ? nil : event
        }) { monitors.append(local) }
    }

    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)!
    }

    /// Keeps the status item from crowding out other menu bar items.
    static func shortened(_ title: String) -> String {
        title.count > 24 ? title.prefix(23) + "…" : title
    }
}

/// Rebuilds the popover's content per account.
private struct PopoverRoot: View {
    @Environment(Store.self) private var store
    var body: some View { MenuBarView().id(store.sessionID) }
}
