import SwiftUI

// Every form is a full screen in the popover's language: header band, task summary, field rows,
// action bar. The main window shows the same views as sheets.
//
// Return runs the primary action as SwiftUI registered it at an earlier render: the shortcut only picks up a new
// closure when the button itself changes (its label or enabled state). So actions read what was typed through
// computed properties, which read @State live, never through `let`s in `body`, or Save sends the time the form
// opened with.

/// Confirms a log: editable duration ("1:30", "1.5h", "90m") pre-rounded per Settings, description,
/// billable, mark task complete.
struct LogView: View {
    @Environment(Store.self) private var store
    @AppStorage("rounding") private var rounding = Rounding.off
    @AppStorage("roundingStep") private var roundingStep = 15
    let timer: TWTimer
    let done: () -> Void
    @State private var duration = ""
    /// Tracked time when the form opened, before rounding.
    @State private var exactDuration = ""
    @State private var description = ""
    @State private var billable = false
    @State private var markComplete = false
    @State private var saving = false
    private var seconds: TimeInterval? { parseDuration(duration) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Log Time", back: done)
            TaskSummary(title: store.title(of: timer), subtitle: store.subtitle(of: timer),
                        url: store.webURL(projectId: timer.projectId, taskId: timer.taskId))
            LogRecovery(timer: timer, done: done)
            Divider()
            FieldRow(label: "Duration", note: durationNote(seconds), noteIsError: !duration.isEmpty && (seconds ?? 0) < 60) {
                DurationField(text: $duration)
            }
            RowDivider()
            NotesRow(text: $description)
            RowDivider()
            FieldRow(label: "Billable") { Toggle("Billable", isOn: $billable).labelsHidden().toggleStyle(.switch) }
            if timer.taskId != nil {
                RowDivider()
                FieldRow(label: "Mark task complete") {
                    Toggle("Mark task complete", isOn: $markComplete).labelsHidden().toggleStyle(.switch)
                }
            }
            ActionBar {
                Button("Cancel", action: done)
                Spacer()
                Button("Log \(seconds.map(\.hoursMinutes) ?? "")") {
                    guard let seconds else { return }
                    saving = true
                    Task {
                        // Unrounded, untouched field → let Teamwork log the live timer time ("complete").
                        if await store.log(timer, seconds: seconds, durationEdited: duration != exactDuration,
                                           description: description, billable: billable, markTaskComplete: markComplete) { done() }
                        saving = false
                    }
                }
                .primaryAction()
                .disabled(saving || (seconds ?? 0) < 60 || store.logAttempts[timer.id] == .uncertain)
            }
        }
        .onAppear {
            let tracked = store.elapsed(timer)
            exactDuration = tracked.hoursMinutes
            // Under a minute tracked (e.g. a timer used as a placeholder): ask for the time instead of showing 0:00.
            duration = tracked < 60 ? "" : rounding.apply(tracked, step: roundingStep).hoursMinutes
            description = timer.description
            billable = timer.billable
        }
    }

    private func durationNote(_ seconds: TimeInterval?) -> String? {
        if duration.isEmpty { return "Enter the time to log, like 1:30, 1.5h or 90m." }
        guard let seconds else { return "Enter a duration like 1:30, 1.5h or 90m." }
        if seconds < 60 { return "Teamwork logs whole minutes; enter at least 1 minute." }
        guard duration != exactDuration else { return nil }
        return "Tracked \(exactDuration)\(rounding != .off ? " · \(rounding.rawValue.lowercased()) to \(roundingStep) min" : "")"
    }
}

/// Logs time to a task or project without a timer: duration, day, notes, billable, mark task complete.
/// On failure the form stays open with its input and the error above the action bar.
struct LogWorkView: View {
    @Environment(Store.self) private var store
    let item: WorkItem
    let done: () -> Void
    @State private var duration = ""
    @State private var day = Date.now
    @State private var choosingDay = false
    @State private var description = ""
    @State private var billable = false
    @State private var markComplete = false
    @State private var saving = false
    private var seconds: TimeInterval? { parseDuration(duration) }

    var body: some View {
        let valid = seconds.map { (60...86400).contains($0) } ?? false
        VStack(spacing: 0) {
            ScreenHeader("Log Time", back: done)
            TaskSummary(title: item.title, subtitle: item.subtitle,
                        url: store.webURL(projectId: item.projectId, taskId: item.taskId))
            Divider()
            FieldRow(label: "Duration", note: durationNote(seconds), noteIsError: !duration.isEmpty && !valid) {
                DurationField(text: $duration)
            }
            RowDivider()
            FieldRow(label: "Date") { DayButton(date: day, open: $choosingDay) }
            if choosingDay {
                MonthCalendar(date: $day, latest: .now) { choosingDay = false }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.s)
            }
            RowDivider()
            NotesRow(text: $description)
            RowDivider()
            FieldRow(label: "Billable") { Toggle("Billable", isOn: $billable).labelsHidden().toggleStyle(.switch) }
            if item.taskId != nil {
                RowDivider()
                FieldRow(label: "Mark task complete") {
                    Toggle("Mark task complete", isOn: $markComplete).labelsHidden().toggleStyle(.switch)
                }
            }
            ActionBar {
                Button("Cancel", action: done)
                Spacer()
                Button("Log \(valid ? seconds!.hoursMinutes : "")") {
                    guard let seconds else { return }
                    saving = true
                    Task {
                        if await store.log(item, seconds: seconds, on: day, description: description, billable: billable,
                                           markTaskComplete: markComplete) { done() }
                        saving = false
                    }
                }
                .primaryAction()
                .disabled(saving || !valid)
            }
        }
        .onAppear {
            description = item.description
            billable = item.billable
        }
    }

    private func durationNote(_ seconds: TimeInterval?) -> String? {
        if duration.isEmpty { return "Enter the time to log, like 1:30, 1.5h or 90m." }
        guard let seconds else { return "Enter a duration like 1:30, 1.5h or 90m." }
        if seconds < 60 { return "Teamwork logs whole minutes; enter at least 1 minute." }
        return seconds > 86400 ? "Enter at most 24 hours." : nil
    }
}

/// Moves a running or paused timer to another project/task, edits its notes and sets its tracked time
/// (a running timer carries on from the new time).
struct EditTimerView: View {
    @Environment(Store.self) private var store
    let timer: TWTimer
    let done: () -> Void
    @State private var target: WorkItem?
    @State private var choosing = false
    @State private var duration = ""
    /// Tracked time when the form opened; the time is only set if the field changes.
    @State private var exactDuration = ""
    @State private var description = ""
    @State private var billable = false
    @State private var saving = false
    private var seconds: TimeInterval? { parseDuration(duration, allowZero: true) }
    private var timeEdited: Bool { duration != exactDuration }

    var body: some View {
        let current = target ?? store.workItem(for: timer)
        // Unchanged, it stays valid even past 24 hours, so a forgotten timer can still be moved.
        let timeValid = !timeEdited || seconds != nil
        VStack(spacing: 0) {
            if choosing {
                ScreenHeader("Change Task") { choosing = false }
                WorkPicker(maxHeight: 360) { item in
                    target = item
                    choosing = false
                }
            } else {
                ScreenHeader("Edit Timer", back: done)
                TaskSummary(title: current?.title ?? store.title(of: timer), subtitle: current?.subtitle,
                            url: store.webURL(projectId: current?.projectId ?? timer.projectId,
                                              taskId: current.map(\.taskId) ?? timer.taskId)) {
                    Button("Change…") { choosing = true }
                        .help("Move this timer to another task or project")
                }
                Divider()
                FieldRow(label: "Tracked", note: timeNote(valid: timeValid, edited: timeEdited), noteIsError: !timeValid) {
                    DurationField(text: $duration)
                }
                RowDivider()
                NotesRow(text: $description)
                RowDivider()
                FieldRow(label: "Billable") { Toggle("Billable", isOn: $billable).labelsHidden().toggleStyle(.switch) }
                ActionBar {
                    Button("Cancel", action: done)
                    Spacer()
                    Button("Save") {
                        saving = true
                        Task {
                            if await store.edit(timer, target: target, description: description, billable: billable,
                                                seconds: timeEdited ? seconds : nil) { done() }
                            saving = false
                        }
                    }
                    .primaryAction()
                    .disabled(saving || !timeValid)
                }
            }
        }
        .onAppear {
            exactDuration = store.elapsed(timer).hoursMinutes
            duration = exactDuration
            description = timer.description
            billable = timer.billable
        }
    }

    private func timeNote(valid: Bool, edited: Bool) -> String? {
        if !valid { return "Enter a time from 0:00 to 24:00, like 1:30, 1.5h or 90m." }
        // Removed idle time, or an edited time Teamwork didn't take.
        return !edited && store.adjustments[timer.id] != nil ? "Teamwork's web app shows the original time until you log it." : nil
    }
}

/// Logs every timer in one go, durations pre-rounded per Settings and still editable.
struct LogAllView: View {
    @Environment(Store.self) private var store
    @AppStorage("rounding") private var rounding = Rounding.off
    @AppStorage("roundingStep") private var roundingStep = 15
    let done: () -> Void

    struct Draft: Identifiable {
        let timer: TWTimer
        let exact: String
        var duration: String
        var billable: Bool
        var included = true
        var id: Int { timer.id }
    }

    @State private var drafts: [Draft] = []
    @State private var saving = false
    private var chosen: [Draft] { drafts.filter(\.included) }

    var body: some View {
        let valid = chosen.allSatisfy { (parseDuration($0.duration) ?? 0) >= 60 }
        let total = chosen.compactMap { parseDuration($0.duration) }.reduce(0, +)
        VStack(spacing: 0) {
            ScreenHeader("Log All", back: done)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($drafts) { $draft in
                        draftRow($draft)
                        LogRecovery(timer: draft.timer)
                        RowDivider()
                    }
                    if rounding != .off {
                        Text("\(rounding.rawValue) to \(roundingStep) min. Edit any duration before logging.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.l)
                            .padding(.vertical, Space.s)
                    }
                }
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            ActionBar {
                Text("Total \(total.hoursMinutes)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: done)
                Button("Log \(chosen.count) Timer\(chosen.count == 1 ? "" : "s")") {
                    saving = true
                    Task {
                        let entries = chosen.compactMap { draft in
                            parseDuration(draft.duration).map { (draft.timer, $0, draft.duration != draft.exact, draft.billable) }
                        }
                        let logged = await store.logAll(entries)
                        drafts.removeAll { logged.contains($0.id) }
                        if logged.count == entries.count { done() }
                        saving = false
                    }
                }
                .primaryAction()
                .disabled(saving || chosen.isEmpty || !valid)
            }
        }
        .onAppear(perform: makeDrafts)
        // Opened before timers finished loading: fill in once they arrive.
        .onChange(of: store.timers.count) {
            if drafts.isEmpty { makeDrafts() }
            else {
                let live = Set(store.timers.map(\.id))
                drafts.removeAll { !live.contains($0.id) }
            }
        }
    }

    private func makeDrafts() {
        drafts = store.timers.map { timer in
            let tracked = store.elapsed(timer)
            return Draft(timer: timer, exact: tracked.hoursMinutes,
                         duration: rounding.apply(tracked, step: roundingStep).hoursMinutes, billable: timer.billable)
        }
    }

    private func draftRow(_ draft: Binding<Draft>) -> some View {
        let timer = draft.wrappedValue.timer
        let title = store.title(of: timer)
        return HStack(spacing: Space.s) {
            Toggle(isOn: draft.included) {}
                .labelsHidden()
                .accessibilityLabel("Include \(title)")
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).fontWeight(.semibold).lineLimit(2)
                if let subtitle = store.subtitle(of: timer) {
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Button { draft.wrappedValue.billable.toggle() } label: {
                    Image(systemName: draft.wrappedValue.billable ? "dollarsign.circle.fill" : "dollarsign.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(draft.wrappedValue.billable ? "Billable" : "Not billable")
                .accessibilityLabel("Billable")
                .accessibilityValue(draft.wrappedValue.billable ? "On" : "Off")
                DurationField(text: draft.duration)
                    .accessibilityLabel("Duration for \(title)")
            }
            .disabled(!draft.wrappedValue.included)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

private struct LogRecovery: View {
    @Environment(Store.self) private var store
    let timer: TWTimer
    var done: (() -> Void)?
    @State private var resolving = false

    var body: some View {
        // Only for a timer still there: a logged one keeps its receipt, and the form would flash this before closing.
        if let status = store.logAttempts[timer.id], !store.isLogging(timer.id), store.timers.contains(where: { $0.id == timer.id }) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(status == .posted ? "This time is already logged. Remove the leftover timer."
                     : "Check Teamwork to see whether this time was logged before choosing an action.")
                if let site = store.webSite { Link("Open Teamwork", destination: site) }
                HStack {
                    Button(status == .posted ? "Remove logged timer" : "Entry exists. Remove timer") { resolve(entryExists: true) }
                    if status == .uncertain {
                        Button("No entry exists. Allow retry") { resolve(entryExists: false) }
                    }
                }
                .disabled(resolving)
            }
            .padding(Space.l)
        }
    }

    private func resolve(entryExists: Bool) {
        resolving = true
        Task {
            await store.resolveLog(timer, entryExists: entryExists)
            if entryExists, !store.timers.contains(where: { $0.id == timer.id }) { done?() }
            resolving = false
        }
    }
}

/// Edits a logged entry, laid out after Harvest's edit form: the task as a field (click to change it), notes beside
/// a large duration, then the day, start time and billable on one line.
struct EditEntryView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let entry: TimeEntry
    let done: () -> Void
    @State private var target: WorkItem?
    @State private var choosing = false
    @State private var choosingDay = false
    @State private var duration = ""
    @State private var start = Date.now
    @State private var description = ""
    @State private var billable = false
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            if choosing {
                ScreenHeader("Change Task") { choosing = false }
                WorkPicker(maxHeight: 360) { item in
                    target = item
                    choosing = false
                }
            } else {
                form
            }
        }
        // Out here, so coming back from the task picker keeps what was typed.
        .onAppear {
            duration = TimeInterval(entry.minutes * 60).hoursMinutes
            start = entry.timeLogged ?? .now
            description = entry.description
            billable = entry.billable
        }
    }

    private var seconds: TimeInterval? { parseDuration(duration) }

    private var form: some View {
        let task = target.map(\.taskName) ?? entry.taskId.flatMap(store.taskName)
        let project = target?.projectName ?? entry.projectId.map(store.projectName)
        let url = store.webURL(projectId: target?.projectId ?? entry.projectId, taskId: target.map(\.taskId) ?? entry.taskId)
        let end = seconds.map { start.addingTimeInterval($0) }
        return VStack(spacing: 0) {
            ScreenHeader(title: "Edit Entry", back: done) {
                if let url {
                    Button { openURL(url) } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PressStyle())
                    .help("Open in Teamwork")
                    .accessibilityLabel("Open in Teamwork")
                }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Button { choosing = true } label: {
                    HStack(spacing: Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            if task != nil, let project {
                                Text(project).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(task ?? project ?? "Time entry").fontWeight(.semibold).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(FieldButtonStyle())
                .help("Move this entry to another task or project")
                .accessibilityLabel("Task")
                .accessibilityValue([task, project].compactMap(\.self).joined(separator: ", "))
                .accessibilityHint("Chooses another task or project")
                HStack(alignment: .top, spacing: Space.s) {
                    TextField("Description", text: $description, prompt: Text("Add a description"), axis: .vertical)
                        .lineLimit(2...6)
                        .filledField()
                    DurationField(text: $duration, large: true, invalid: (seconds ?? 0) < 60)
                }
                .fixedSize(horizontal: false, vertical: true)
                if (seconds ?? 0) < 60 {
                    Text("Enter at least 1 minute, like 1:30, 1.5h or 90m.").font(.callout).foregroundStyle(.red)
                }
                HStack(spacing: Space.xs) {
                    DayButton(date: start, open: $choosingDay)
                    TimeField(date: $start)
                    if let end, (seconds ?? 0) >= 60 {
                        // Where the entry ends, so a changed start or duration shows its span.
                        Text("– \(end.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Ends \(end.formatted(date: .omitted, time: .shortened))")
                    }
                    Spacer(minLength: Space.s)
                    Toggle("Billable", isOn: $billable).toggleStyle(.switch).fixedSize()
                }
                if choosingDay {
                    MonthCalendar(date: $start) { choosingDay = false }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            ActionBar {
                Button("Cancel", action: done)
                Spacer()
                Button("Save") {
                    guard let seconds else { return }
                    saving = true
                    Task {
                        if await store.updateEntry(entry, target: target, seconds: seconds, start: start,
                                                   description: description, billable: billable) {
                            done()
                        }
                        saving = false
                    }
                }
                .primaryAction()
                .disabled(saving || (seconds ?? 0) < 60)
            }
        }
    }
}

/// The day of `date` as a field that says it in words ("Today", "Yesterday", "Mon 19 Oct"), opening and closing a
/// `MonthCalendar` the form places under it. Inline rather than a popover: a second window over the menu-bar
/// popover takes the focus, and the popover closes when it loses it.
struct DayButton: View {
    let date: Date
    @Binding var open: Bool

    var body: some View {
        Button { open.toggle() } label: {
            Label {
                Text(Self.name(date))
            } icon: {
                Image(systemName: "calendar").foregroundStyle(Brand.purple)
            }
        }
        .buttonStyle(FieldButtonStyle(open: open))
        .help(open ? "Close the calendar" : "Choose the day")
        .accessibilityLabel("Day")
        .accessibilityValue(date.formatted(date: .complete, time: .omitted))
    }

    static func name(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return calendar.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// A month to pick a day from, drawn like the week strip: the day in a brand-purple circle, today in purple, a faint
/// circle under the pointer. A click or Today picks and closes; ← → ↑ ↓ move the day while it's open. Picking keeps
/// `date`'s time of day. Days after `latest` can't be picked.
struct MonthCalendar: View {
    @Binding var date: Date
    var latest: Date?
    let close: () -> Void
    /// The first of the month shown.
    @State private var month = Date.now
    @FocusState private var focused: Bool
    private var calendar: Calendar { .current }

    var body: some View {
        let first = calendar.dateInterval(of: .weekOfYear, for: month)!.start
        // Always six weeks, so the panel keeps its height from month to month.
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.xxs) {
                Text(month.formatted(.dateTime.month(.wide).year())).fontWeight(.semibold)
                Spacer()
                Button("Today") { pick(.now) }
                    .foregroundStyle(Brand.purple)
                    .fontWeight(.medium)
                    .padding(.trailing, Space.xxs)
                Button { show(-1) } label: { chevron("chevron.left") }
                    .help("Previous month")
                    .accessibilityLabel("Previous month")
                Button { show(1) } label: { chevron("chevron.right") }
                    .help("Next month")
                    .accessibilityLabel("Next month")
                    .disabled(latest.map { calendar.date(byAdding: .month, value: 1, to: month)! > $0 } ?? false)
            }
            .buttonStyle(PressStyle())
            Grid(horizontalSpacing: Space.xxs, verticalSpacing: 2) {
                GridRow {
                    ForEach(weekdays.indices, id: \.self) { index in
                        Text(weekdays[index]).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                .accessibilityHidden(true)
                ForEach(0..<6, id: \.self) { week in
                    GridRow {
                        ForEach(days[week * 7 ..< week * 7 + 7], id: \.self) { day in
                            CalendarDay(day: day, selected: calendar.isDate(day, inSameDayAs: date),
                                        inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                        enabled: allowed(day)) { pick(day) }
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false) // as wide as the grid; the header's Spacer takes the rest
        .padding(Space.s)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        // Takes the keys while open, so the arrows move the day; the selected circle shows where.
        .focusable(interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let step = switch press.key {
            case .leftArrow: -1
            case .rightArrow: 1
            case .upArrow: -7
            default: 7
            }
            if let day = calendar.date(byAdding: .day, value: step, to: date), allowed(day) { set(day) }
            return .handled
        }
        .onAppear {
            month = calendar.dateInterval(of: .month, for: date)!.start
            focused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar")
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(.rect)
    }

    private func allowed(_ day: Date) -> Bool {
        latest.map { calendar.startOfDay(for: day) <= $0 } ?? true
    }

    private func show(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }

    /// Moves `date` to `day`, keeping its time of day, and shows that day's month.
    private func set(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
        month = calendar.dateInterval(of: .month, for: day)!.start
    }

    private func pick(_ day: Date) {
        set(day)
        close()
    }
}

private struct CalendarDay: View {
    let day: Date
    let selected: Bool
    let inMonth: Bool
    let enabled: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        let today = Calendar.current.isDateInToday(day)
        Button(action: pick) {
            Text(day.formatted(.dateTime.day()))
                .monospacedDigit()
                .fontWeight(selected || today ? .semibold : .regular)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : today ? AnyShapeStyle(Brand.purple)
                                 : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 32, height: 30)
                .background(selected ? AnyShapeStyle(Brand.purpleFill) : AnyShapeStyle(Brand.purple.opacity(hovering ? 0.1 : 0)),
                            in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 && enabled }
        .animation(hovering ? nil : .easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The time of day in `date` as a borderless AppKit date picker in the filled-field look: click the hour or the
/// minute and type, or step it with ↑ ↓. It follows the system's 12- or 24-hour clock.
struct TimeField: View {
    @Binding var date: Date

    var body: some View {
        TimeInput(date: $date)
            .fixedSize()
            .padding(.vertical, -2) // AppKit's own inset, so the box is as tall as the day beside it
            .filledField()
            .help("Start time")
    }
}

private struct TimeInput: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.setAccessibilityLabel("Start time")
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        if picker.dateValue != date { picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    @MainActor final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ picker: NSDatePicker) { date.wrappedValue = picker.dateValue }
    }
}

/// Right-aligned h:mm field with forgiving input ("1:30", "530", "1.5h", "90m"). A click or Tab selects the
/// whole value, so typing replaces it, and digits get their colon as you type (`durationWithColon`).
struct DurationField: View {
    @Binding var text: String
    /// Harvest-size digits beside a form's notes, stretched to their height.
    var large = false
    /// Rings the field in red; the form says why underneath.
    var invalid = false

    var body: some View {
        DurationInput(text: $text, large: large)
            .frame(width: large ? 96 : 72)
            .frame(maxHeight: large ? .infinity : nil)
            .filledField()
            .overlay {
                if invalid { RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.7)) }
            }
            .help("1:30, 530, 1.5h or 90m")
    }
}

/// AppKit underneath: SwiftUI's TextField puts the caret where you click and can't be told to select all.
private struct DurationInput: NSViewRepresentable {
    @Binding var text: String
    var large = false

    func makeNSView(context: Context) -> SelectAllField {
        let field = SelectAllField()
        field.placeholderString = "1:30"
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: large ? 22 : NSFont.systemFontSize, weight: .semibold)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.setAccessibilityLabel("Duration")
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: SelectAllField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    /// Large: as tall as offered, so a click anywhere in the box lands in the field (the digits sit at its top).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: SelectAllField, context: Context) -> CGSize? {
        guard large else { return nil }
        let fitting = field.intrinsicContentSize
        return CGSize(width: proposal.width ?? fitting.width, height: max(fitting.height, proposal.height ?? 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let shown = durationWithColon(field.stringValue, previous: text.wrappedValue)
            if shown != field.stringValue {
                field.stringValue = shown
                field.currentEditor()?.selectedRange = NSRange(location: (shown as NSString).length, length: 0)
            }
            text.wrappedValue = shown
        }
    }
}

/// Selects its whole value when it takes focus, by click or Tab; a second click places the caret as usual.
final class SelectAllField: NSTextField {
    private var selectAfterClick = false

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        currentEditor()?.selectAll(nil)
        selectAfterClick = NSApp.currentEvent?.type == .leftMouseDown
        return true
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event) // the field editor tracks the click and places the caret
        if selectAfterClick { currentEditor()?.selectAll(nil) }
        selectAfterClick = false
    }
}
