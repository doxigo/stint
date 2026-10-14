import AppKit
import UserNotifications

/// "Forgot to track" reminders (opt-in), the alert for a timer left running over 8 hours,
/// and the end-of-day nudge to log what's still on the timers.
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static var remindersEnabled: Bool { UserDefaults.standard.bool(forKey: "remindersEnabled") }
    static var longTimerAlert: Bool { UserDefaults.standard.object(forKey: "longTimerAlert") as? Bool ?? true }
    static var endOfDayNudge: Bool { UserDefaults.standard.object(forKey: "endOfDayNudge") as? Bool ?? true }
    static let interval: TimeInterval = 30 * 60
    static let longTimer: TimeInterval = 8 * 3600

    weak var store: Store?
    private var lastTracked = Date.now
    private var snoozedUntil = Date.distantPast
    private var alerted: Set<Int> = []
    private var nudgedDay: Date?

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "reminder", actions: [
                UNNotificationAction(identifier: "resume", title: "Resume Last Timer"),
                UNNotificationAction(identifier: "snooze", title: "Snooze 1 Hour"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: "endOfDay", actions: [
                UNNotificationAction(identifier: "logAll", title: "Log All…", options: .foreground),
            ], intentIdentifiers: []),
        ])
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func reset() {
        lastTracked = .now
        snoozedUntil = .distantPast
        alerted = []
        nudgedDay = nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Runs after each poll.
    func check(now: Date = .now) {
        guard let store, store.isSignedIn else { return }
        if let timer = store.runningTimer {
            lastTracked = now
            if Self.longTimerAlert, store.elapsed(timer, at: now) >= Self.longTimer, alerted.insert(timer.id).inserted {
                post("long-\(timer.id)", "Timer still running",
                     "“\(store.title(of: timer))” has been running for \(store.elapsed(timer, at: now).spoken).")
            }
        } else if Self.remindersEnabled, Self.isWorkingHours(now), now >= snoozedUntil,
                  now.timeIntervalSince(lastTracked) >= Self.interval {
            lastTracked = now
            post("reminder", "No timer running", "Start one so today's time gets logged.", category: "reminder")
        }

        // Once per weekday, from 17:00: timers left unlogged.
        let today = Calendar.current.startOfDay(for: now)
        if Self.endOfDayNudge, Self.isAfterWork(now), nudgedDay != today, !store.timers.isEmpty {
            nudgedDay = today
            let count = store.timers.count
            post("endOfDay", "\(count) timer\(count == 1 ? "" : "s") not logged",
                 "Log today's time before you finish.", category: "endOfDay")
        }
    }

    /// Monday–Friday, 9:00–17:00 local time.
    nonisolated static func isWorkingHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday … 7 = Saturday
        return (2...6).contains(weekday) && (9..<17).contains(calendar.component(.hour, from: date))
    }

    /// Monday–Friday from 17:00 local time.
    nonisolated static func isAfterWork(_ date: Date, calendar: Calendar = .current) -> Bool {
        (2...6).contains(calendar.component(.weekday, from: date)) && calendar.component(.hour, from: date) >= 17
    }

    private func post(_ id: String, _ title: String, _ body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        await MainActor.run {
            switch action {
            case "resume": Task { await self.store?.resumeLast() }
            case "snooze": snoozedUntil = .now.addingTimeInterval(3600)
            case "logAll": store?.showLogAll()
            default: if category == "endOfDay" { store?.showLogAll() } else { NSApp.activate() }
            }
        }
    }
}
