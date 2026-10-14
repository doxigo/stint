import SwiftUI

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
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Timer").font(.title2.bold())
            if choosing {
                WorkPicker(maxHeight: 260) { item in
                    target = item
                    choosing = false
                }
                Button("Back") { choosing = false }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(current?.title ?? store.title(of: timer)).lineLimit(1)
                        if let subtitle = current?.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Change…") { choosing = true }
                }
                LabeledContent("Tracked") { TimerText(timer: timer) }
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                Toggle("Billable", isOn: $billable)
                HStack {
                    Spacer()
                    Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        saving = true
                        Task {
                            if await store.edit(timer, target: target, description: description, billable: billable) { done() }
                            saving = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(Brand.purpleFill) // filled default button: fixed purple keeps white text readable in Dark Mode
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Log All Timers").font(.title2.bold())
            ForEach($drafts) { $draft in
                HStack(spacing: 8) {
                    Toggle(isOn: $draft.included) {}
                        .labelsHidden()
                        .accessibilityLabel("Include \(store.title(of: draft.timer))")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.title(of: draft.timer)).lineLimit(1)
                        if let subtitle = store.subtitle(of: draft.timer) {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Group {
                        Button { draft.billable.toggle() } label: {
                            Image(systemName: draft.billable ? "dollarsign.circle.fill" : "dollarsign.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(draft.billable ? "Billable" : "Not billable")
                        .accessibilityLabel("Billable")
                        .accessibilityValue(draft.billable ? "On" : "Off")
                        TextField("Duration", text: $draft.duration)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .monospacedDigit()
                            .foregroundStyle((parseDuration(draft.duration) ?? 0) >= 60 ? .primary : Color.red)
                            .accessibilityLabel("Duration for \(store.title(of: draft.timer))")
                    }
                    .disabled(!draft.included)
                }
            }
            if rounding != .off {
                Text("\(rounding.rawValue) to \(roundingStep) min. Edit any duration before logging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Total \(total.hoursMinutes)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Log \(chosen.count) Timer\(chosen.count == 1 ? "" : "s")") {
                    saving = true
                    Task {
                        let entries = chosen.compactMap { draft in
                            parseDuration(draft.duration).map { (draft.timer, $0, draft.duration != draft.exact, draft.billable) }
                        }
                        if await store.logAll(entries) == entries.count { done() }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .tint(Brand.purpleFill) // filled default button: fixed purple keeps white text readable in Dark Mode
                .disabled(saving || chosen.isEmpty || !valid)
            }
        }
        .onAppear {
            drafts = store.timers.map { timer in
                let tracked = store.elapsed(timer)
                return Draft(timer: timer, exact: tracked.hoursMinutes,
                             duration: rounding.apply(tracked, step: roundingStep).hoursMinutes, billable: timer.billable)
            }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Time Entry").font(.title2.bold())
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.taskId.flatMap(store.taskName) ?? entry.projectId.map(store.projectName) ?? "Time entry")
                if entry.taskId != nil, let projectId = entry.projectId {
                    Text(store.projectName(projectId)).font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Duration") {
                TextField("Duration", text: $duration, prompt: Text("1:30, 1.5h, 90m"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .monospacedDigit()
            }
            if (seconds ?? 0) < 60 {
                Label("Enter a duration of at least 1 minute, like 1:30, 1.5h or 90m.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            DatePicker("Start", selection: $start)
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Toggle("Billable", isOn: $billable)
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
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
                .keyboardShortcut(.defaultAction)
                .tint(Brand.purpleFill) // filled default button: fixed purple keeps white text readable in Dark Mode
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
