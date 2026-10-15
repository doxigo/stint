import SwiftUI

// Every form is a full screen in the popover's language: header band, task summary, field rows,
// action bar. The main window shows the same views as sheets.

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

    var body: some View {
        let seconds = parseDuration(duration)
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
    @State private var description = ""
    @State private var billable = false
    @State private var markComplete = false
    @State private var saving = false

    var body: some View {
        let seconds = parseDuration(duration)
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
            FieldRow(label: "Date") {
                DatePicker("Date", selection: $day, in: ...Date.now, displayedComponents: .date).labelsHidden()
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

/// Moves a running or paused timer to another project/task and edits its notes; the tracked time stays.
struct EditTimerView: View {
    @Environment(Store.self) private var store
    let timer: TWTimer
    let done: () -> Void
    @State private var target: WorkItem?
    @State private var choosing = false
    @State private var description = ""
    @State private var billable = false
    @State private var saving = false

    var body: some View {
        let current = target ?? store.workItem(for: timer)
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
                FieldRow(label: "Tracked") { TimerText(timer: timer).foregroundStyle(.secondary) }
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
                            if await store.edit(timer, target: target, description: description, billable: billable) { done() }
                            saving = false
                        }
                    }
                    .primaryAction()
                    .disabled(saving)
                }
            }
        }
        .onAppear {
            description = timer.description
            billable = timer.billable
        }
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

    var body: some View {
        let chosen = drafts.filter(\.included)
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
        if let status = store.logAttempts[timer.id], !store.isLogging(timer.id) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(status == .posted ? "This time is already logged. Remove the leftover timer."
                     : "Check Teamwork to see whether this time was logged before choosing an action.")
                if let site = store.site { Link("Open Teamwork", destination: site) }
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

/// Edits a logged entry: duration, start, description, billable.
struct EditEntryView: View {
    @Environment(Store.self) private var store
    let entry: TimeEntry
    let done: () -> Void
    @State private var duration = ""
    @State private var start = Date.now
    @State private var description = ""
    @State private var billable = false
    @State private var saving = false

    var body: some View {
        let seconds = parseDuration(duration)
        let task = entry.taskId.flatMap(store.taskName)
        let project = entry.projectId.map(store.projectName)
        VStack(spacing: 0) {
            ScreenHeader("Edit Entry", back: done)
            TaskSummary(title: task ?? project ?? "Time entry", subtitle: task == nil ? nil : project,
                        url: store.webURL(projectId: entry.projectId, taskId: entry.taskId))
            Divider()
            FieldRow(label: "Duration",
                     note: (seconds ?? 0) < 60 ? "Enter at least 1 minute, like 1:30, 1.5h or 90m." : nil,
                     noteIsError: true) {
                DurationField(text: $duration)
            }
            RowDivider()
            FieldRow(label: "Start") {
                DatePicker("Start", selection: $start).labelsHidden()
            }
            RowDivider()
            NotesRow(text: $description)
            RowDivider()
            FieldRow(label: "Billable") { Toggle("Billable", isOn: $billable).labelsHidden().toggleStyle(.switch) }
            ActionBar {
                Button("Cancel", action: done)
                Spacer()
                Button("Save") {
                    guard let seconds else { return }
                    saving = true
                    Task {
                        if await store.updateEntry(entry, seconds: seconds, start: start, description: description, billable: billable) {
                            done()
                        }
                        saving = false
                    }
                }
                .primaryAction()
                .disabled(saving || (seconds ?? 0) < 60)
            }
        }
        .onAppear {
            duration = TimeInterval(entry.minutes * 60).hoursMinutes
            start = entry.timeLogged ?? .now
            description = entry.description
            billable = entry.billable
        }
    }
}

/// Right-aligned h:mm field with forgiving input ("1:30", "1.5h", "90m").
struct DurationField: View {
    @Binding var text: String

    var body: some View {
        TextField("Duration", text: $text, prompt: Text("1:30"))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .font(.body.weight(.semibold))
            .frame(width: 72)
            .filledField()
            .help("1:30, 1.5h or 90m")
    }
}
