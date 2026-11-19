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
        // Closes and resizes at once, like a menu. While the close animation runs the popover still counts as
        // shown, so a quick second click on the item was lost (measured). Opening has its own motion (`popIn`).
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
        // The item changes width when a timer starts or its text grows, and macOS then moves it. The popover
        // doesn't follow by itself, which left its arrow beside the item.
        item.button?.postsFrameChangedNotifications = true
        for name in [NSView.frameDidChangeNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { self?.reanchor(movedBy: sender) }
            }
        }
        track()
    }

    /// Points the open popover at the status item again, once the item or its window (`sender`) has moved.
    private func reanchor(movedBy sender: ObjectIdentifier?) {
        guard popover.isShown, let button = item.button,
              sender == ObjectIdentifier(button) || sender == button.window.map(ObjectIdentifier.init) else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) // shown already: only moves it
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
            return show(Self.symbol("timer"), title: "", label: "Stint", in: button)
        }
        let state = timer.running ? "Running" : "Paused"
        // Shape, not just colour, tells running from paused: pause while running, as in Harvest.
        let glyph = Self.symbol(timer.running ? "pause.fill" : "play.fill")
        let highlight = defaults.bool(forKey: "menuBarHighlight") // on by default: `registerSettingDefaults`
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
        popIn(from: button)
        popover.contentViewController?.view.window?.makeKey() // takes typing even while another app is active
        // Active before the first click lands. macOS declines plain activate() here (the item's click
        // reaches the app through MenuBarAgent), so the popover's first click activated the app instead,
        // and that activation closed the menu the same click had opened (the Open Window chevron).
        // After makeKey, so the popover stays the key window once the app is active.
        NSApp.activate(ignoringOtherApps: true)
        button.highlight(true)
        watchOutside()
    }

    /// The popover grows out of the status item: a short fade, and a touch of scale from the arrow's tip (the fade
    /// alone under Reduce Motion). Ours rather than `animates`, which also animates the close and every resize
    /// (see init). The window is there from the first frame, so no click is lost to the motion.
    private func popIn(from button: NSStatusBarButton) {
        guard let window = content.view.window else { return }
        let duration = 0.15, scale = 0.96
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        // The window's top view, so the popover's own background and arrow scale with the content.
        var frame: NSView = content.view
        while let parent = frame.superview { frame = parent }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = frame.layer,
              let bar = button.window else { return }
        let tipX = bar.convertToScreen(button.convert(button.bounds, to: nil)).midX - window.frame.minX
        let tip = frame.convert(NSPoint(x: tipX, y: window.frame.height), from: nil)
        // A layer scales about its anchor point; the shift keeps the arrow's tip in place instead.
        let anchor = CGPoint(x: layer.bounds.minX + layer.anchorPoint.x * layer.bounds.width,
                             y: layer.bounds.minY + layer.anchorPoint.y * layer.bounds.height)
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = CATransform3DMakeAffineTransform(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale, tx: (1 - scale) * (tip.x - anchor.x), ty: (1 - scale) * (tip.y - anchor.y)))
        grow.duration = duration
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(grow, forKey: "popIn") // presentation only: the layer itself stays as AppKit set it
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
