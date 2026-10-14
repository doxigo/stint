import SwiftUI

// Shared building blocks for every popover screen (and the main window's sheets), so all of them read
// as one design: slate header band, full-width rows with inset dividers, small-caps group labels,
// field rows, and the bottom action bar.

/// Slate header band: centred title with the brand's pink full stop, optional Back, optional trailing view.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text("\(title)\(Text(".").foregroundStyle(Brand.pink))")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 72) // clear of Back and the trailing view
            HStack {
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Back")
                    .accessibilityLabel("Back")
                }
                Spacer()
                trailing
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity)
        .background(Brand.slate)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, back: (() -> Void)? = nil) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

/// Divider between rows, inset to the text edge.
struct RowDivider: View {
    var body: some View { Divider().padding(.leading, Space.l) }
}

/// Bottom bar: the same large bordered controls as the day screen. Put the primary action last.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Space.s) { content }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
        }
    }
}

/// The task a form is about: link title (opens in Teamwork) and project.
struct TaskSummary<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let url: URL?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                TitleLink(title: title, url: url)
                if let subtitle { Text(subtitle).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

extension TaskSummary where Trailing == EmptyView {
    init(title: String, subtitle: String?, url: URL?) {
        self.init(title: title, subtitle: subtitle, url: url) { EmptyView() }
    }
}

/// A form row: label on the left, control on the right, optional note underneath.
struct FieldRow<Control: View>: View {
    let label: String
    var note: String?
    var noteIsError = false
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.m) {
                Text(label)
                Spacer(minLength: Space.m)
                control
            }
            if let note {
                Label(note, systemImage: noteIsError ? "exclamationmark.circle" : "info.circle")
                    .labelStyle(.titleOnly)
                    .font(.callout)
                    .foregroundStyle(noteIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(minHeight: 44)
    }
}

/// Free-text notes as a full-width row.
struct NotesRow: View {
    @Binding var text: String

    var body: some View {
        TextField("Description", text: $text, prompt: Text("Add a description"), axis: .vertical)
            .lineLimit(2...5)
            .filledField()
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
    }
}

extension View {
    /// The quiet filled text-field look used by the search field and every form field.
    func filledField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
    }

    /// The one filled action on a screen: brand purple, Return.
    func primaryAction() -> some View {
        buttonStyle(.borderedProminent)
            .tint(Brand.purpleFill) // fixed purple keeps white text readable in Dark Mode
            .keyboardShortcut(.defaultAction)
    }
}
