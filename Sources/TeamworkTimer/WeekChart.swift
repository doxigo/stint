import AppKit
import Charts
import SwiftUI

/// This Week's logged time per weekday against each day's target. Today adds its timers (not logged yet) as a
/// lighter segment. Click a day to jump to its entries; hover for the exact time.
struct WeekChart: View {
    @Environment(Store.self) private var store
    let week: DateInterval
    let entries: [TimeEntry]
    /// A day's start, when its bar is clicked.
    let select: (Date) -> Void
    @State private var hovered: Date?

    /// #6438E0 in Light Mode. In Dark Mode a step between it (2.5:1 on the window, too faint for a bar)
    /// and `Brand.purple`'s text tint (too light for a large fill): 4.3:1, validated with the dataviz checks.
    private static let bar = Color(nsColor: NSColor(name: "twChartPurple") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 138 / 255, green: 108 / 255, blue: 242 / 255, alpha: 1)
            : NSColor(red: 100 / 255, green: 56 / 255, blue: 224 / 255, alpha: 1)
    })
    private static let barWidth: CGFloat = 24

    var body: some View {
        // Once a minute, not on the store's per-second clock: that would redraw the whole chart every second.
        // `.now`, not the entry's date: that's the start of the minute, a minute behind the timer rows.
        TimelineView(.everyMinute) { _ in
            let days = days(now: .now)
            VStack(alignment: .leading, spacing: Space.s) {
                chart(days)
                legend(days)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
    }

    private struct Day: Identifiable {
        let start: Date
        let label: String
        let logged: TimeInterval
        /// Today's timers, not logged yet.
        let tracked: TimeInterval
        let target: TimeInterval?
        let isToday: Bool
        let isFuture: Bool
        var id: Date { start }
        var total: TimeInterval { logged + tracked }
        var met: Bool { target.map { total >= $0 } ?? false }

        var spoken: String {
            var parts = [logged > 0 ? "\(logged.spoken) logged" : "nothing logged"]
            if tracked > 0 { parts.append("\(tracked.spoken) in timers") }
            if let target { parts.append(met ? "target of \(target.spoken) met" : "target \(target.spoken)") }
            return parts.joined(separator: ", ")
        }
    }

    private func days(now: Date) -> [Day] {
        let calendar = Calendar.current
        var logged: [Date: TimeInterval] = [:]
        for entry in entries {
            logged[calendar.startOfDay(for: entry.timeLogged ?? week.start), default: 0] += TimeInterval(entry.minutes * 60)
        }
        let today = calendar.startOfDay(for: now)
        let tracked = store.timers.reduce(0) { $0 + store.elapsed($1, at: now) }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.map { start in
            Day(start: start, label: start.formatted(.dateTime.weekday(.abbreviated)),
                logged: logged[start] ?? 0, tracked: start == today ? tracked : 0,
                target: store.target(in: calendar.dateInterval(of: .day, for: start)!),
                isToday: start == today, isFuture: start > today)
        }
    }

    private func chart(_ days: [Day]) -> some View {
        let shown = days.filter { !$0.isFuture }
        // Headroom above the tallest bar or target for the met checkmark; the top needn't be a gridline.
        let top = max(1, days.map { max($0.total, $0.target ?? 0) }.max()! / 3600) * 1.15
        let step: Double = top <= 6 ? 2 : top <= 16 ? 4 : 8
        let hoveredDay = shown.first { $0.start == hovered }
        return Chart {
            ForEach(days.filter(\.isToday)) { day in
                RectangleMark(x: .value("Day", day.label), width: .ratio(0.8))
                    .foregroundStyle(Self.bar.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
            }
            if let day = hoveredDay {
                RectangleMark(x: .value("Day", day.label), width: .ratio(0.8))
                    .foregroundStyle(Color.primary.opacity(0.06))
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
            }
            ForEach(shown) { day in
                BarMark(x: .value("Day", day.label), yStart: .value("Hours", 0), yEnd: .value("Hours", day.logged / 3600),
                        width: .fixed(Self.barWidth))
                    .foregroundStyle(Self.bar)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: day.tracked > 0 ? 0 : 4,
                                                      topTrailingRadius: day.tracked > 0 ? 0 : 4))
                    // All in the label: a mark's accessibilityValue doesn't reach the macOS accessibility tree.
                    .accessibilityLabel("\(day.start.formatted(.dateTime.weekday(.wide).month().day())), \(day.spoken)")
                    .annotation(position: .top, spacing: 2) { if day.met && day.tracked == 0 { metMark } }
                if day.tracked > 0 {
                    BarMark(x: .value("Day", day.label), yStart: .value("Hours", day.logged / 3600),
                            yEnd: .value("Hours", day.total / 3600), width: .fixed(Self.barWidth))
                        .foregroundStyle(Self.bar.opacity(0.4))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                        .offset(yStart: day.logged > 0 ? -2 : 0) // 2-pt surface gap above the logged part
                        .accessibilityHidden(true) // the logged bar's value includes it
                        .annotation(position: .top, spacing: 2) { if day.met { metMark } }
                }
                if let target = day.target {
                    // Ink above an open bar; a surface-coloured notch across a bar that reached it.
                    RectangleMark(x: .value("Day", day.label), y: .value("Target", target / 3600),
                                  width: .fixed(Self.barWidth + 10), height: .fixed(2))
                        .foregroundStyle(day.met ? AnyShapeStyle(.background) : AnyShapeStyle(Color.primary.opacity(0.7)))
                        .accessibilityHidden(true)
                }
            }
            if let day = hoveredDay {
                // Last, so it draws over the bars; beside the column, toward the middle, so it never covers
                // the bar it describes.
                RectangleMark(x: .value("Day", day.label), width: .ratio(0.8))
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
                    .annotation(position: shown.firstIndex { $0.id == day.id }! < 4 ? .trailing : .leading,
                                alignment: .top, spacing: Space.xxs,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tooltip(day)
                    }
            }
        }
        .chartXScale(domain: days.map(\.label))
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks { value in
                let day = days.first { $0.label == value.as(String.self) }
                AxisValueLabel {
                    HStack(spacing: Space.xxs) {
                        if day?.isToday == true && store.runningTimer != nil { LiveDot() }
                        Text(value.as(String.self) ?? "")
                            .fontWeight(day?.isToday == true ? .semibold : .regular)
                            .foregroundStyle(day?.isToday == true ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(stride(from: 0, through: top, by: step))) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))h").monospacedDigit() }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(.rect)
                    .onContinuousHover { phase in
                        if case .active(let point) = phase {
                            hovered = day(at: point, in: shown, proxy, geometry)?.start
                        } else {
                            hovered = nil
                        }
                    }
                    .onTapGesture { point in
                        if let day = day(at: point, in: shown, proxy, geometry) { select(day.start) }
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 140)
    }

    /// Above a bar that reached its target.
    private var metMark: some View {
        Image(systemName: "checkmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Self.bar)
            .accessibilityHidden(true)
    }

    private func day(at point: CGPoint, in days: [Day], _ proxy: ChartProxy, _ geometry: GeometryProxy) -> Day? {
        guard let plot = proxy.plotFrame,
              let label = proxy.value(atX: point.x - geometry[plot].minX, as: String.self) else { return nil }
        return days.first { $0.label == label }
    }

    private func tooltip(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.start.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(day.target.map { "\(day.logged.hoursMinutes) of \($0.hoursMinutes)" } ?? day.logged.hoursMinutes)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            if day.tracked > 0 {
                Text("+ \(day.tracked.hoursMinutes) in timers")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.xxs + 2)
        .background(.background, in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }

    /// Keys for what's on the chart; the timers key only when there are some.
    private func legend(_ days: [Day]) -> some View {
        HStack(spacing: Space.m) {
            key("Logged") { RoundedRectangle(cornerRadius: 2).fill(Self.bar).frame(width: 8, height: 8) }
            if days.contains(where: { $0.tracked > 0 }) {
                key("Timers") { RoundedRectangle(cornerRadius: 2).fill(Self.bar.opacity(0.4)).frame(width: 8, height: 8) }
            }
            if days.contains(where: { $0.target != nil }) {
                key("Target") { Capsule().fill(Color.primary.opacity(0.7)).frame(width: 12, height: 2) }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true) // each bar's VoiceOver value names logged, timers and target
    }

    private func key(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: Space.xxs + 2) {
            swatch()
            Text(title)
        }
    }
}
