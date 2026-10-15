import SwiftUI

/// The status item, the app's main timer display (as in Harvest): live time of the current timer,
/// including one started on the web, or an icon when nothing is tracked. A click opens the popover,
/// except on the Time badge's play/pause segment, which pauses or resumes the timer.
/// Hand-made rather than a MenuBarExtra: macOS handles clicks on a MenuBarExtra item itself and only
/// asks SwiftUI to open its window, so no part of that item could act as a button.
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
    /// The click that closed the popover, so that same click on the item doesn't reopen it.
    private var closingClick: TimeInterval?

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
        popover.behavior = .transient
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
        // Shape, not just colour, tells running from paused.
        let glyph = Self.symbol(timer.running ? "play.fill" : "pause.fill")
        guard style != .icon else { return show(glyph, title: "", label: state, in: button) }
        // Plain text on the store's clock; see `Store.menuBarNow` for why not TimerText.
        let elapsed = store.elapsed(timer, at: store.menuBarNow)
        let time = defaults.bool(forKey: "menuBarSeconds") ? elapsed.clock : elapsed.hoursMinutes
        let label = "\(state), \(elapsed.spoken)"
        switch style {
        case .badge:
            let highlighted = timer.running && defaults.object(forKey: "menuBarHighlight") as? Bool ?? true
            show(MenuBarBadge.image(running: timer.running, highlighted: highlighted, time: time), title: "", label: label, in: button)
        // Leading space: the button sets its title flush against the image.
        case .taskAndTime: show(glyph, title: " \(Self.shortened(store.title(of: timer)))  \(time)", label: label, in: button)
        case .time, .icon: show(glyph, title: " \(time)", label: label, in: button)
        }
    }

    private func show(_ image: NSImage, title: String, label: String, in button: NSStatusBarButton) {
        if button.image !== image { button.image = image }
        if button.title != title {
            button.title = title
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(label)
    }

    @objc private func clicked(_ button: NSStatusBarButton) {
        if NSApp.currentEvent?.type != .rightMouseDown, isOnSegment(button), let timer = store.activeTimer {
            Task { await store.toggle(timer) }
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else if NSApp.currentEvent?.timestamp != closingClick {
            NotificationCenter.default.post(name: Self.willOpen, object: nil)
            NSApp.activate() // so the search field takes typing
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)
        }
    }

    /// Whether the pointer is over the badge's play/pause segment. Measured from the pointer's screen
    /// position against the copy of the item under it: macOS draws one copy per display, and the click
    /// event it passes on always lands in the item's centre (measured on macOS 27).
    private func isOnSegment(_ button: NSStatusBarButton) -> Bool {
        guard UserDefaults.standard.string(forKey: "menuBarStyle") == MenuBarStyle.badge.rawValue,
              store.activeTimer != nil, let image = button.image else { return false }
        let mouse = NSEvent.mouseLocation
        guard let copy = NSApp.windows.first(where: { $0.className == "NSStatusBarWindow" && $0.frame.contains(mouse) })
        else { return false }
        // AppKit centres the image in the item; the margin left of it counts as the segment too.
        return mouse.x - copy.frame.minX < (copy.frame.width - image.size.width) / 2 + MenuBarBadge.segment
    }

    /// A transient popover closes on the mouse-down outside it, before the item's action runs.
    func popoverWillClose(_ notification: Notification) {
        closingClick = NSApp.currentEvent?.timestamp
    }

    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(false)
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
