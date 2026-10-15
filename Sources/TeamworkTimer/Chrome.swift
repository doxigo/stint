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
            ErrorBanner()
            Divider()
            HStack(spacing: Space.s) { content }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
        }
    }
}

struct ErrorBanner: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let error = store.errorMessage {
            HStack(alignment: .top) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
            }
            .foregroundStyle(.red)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
        }
    }
}

/// `Store.toast` as a purple pill, laid over a view so it never moves the layout. It eases a few points in
/// from `edge` (a plain fade under Reduce Motion) and leaves after 2 s, on a click, or for a newer toast.
/// ponytail: one-shot transitions only; anything repeating would redraw the popover nonstop (see LiveDot).
struct ToastOverlay: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var edge: VerticalEdge = .top

    var body: some View {
        ZStack {
            if let toast = store.toast {
                Button(action: store.dismissToast) {
                    Label(toast.message, systemImage: toast.symbol)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.xs)
                        // Fixed brand purple in both appearances (white stays at 6.9:1); the hairline
                        // separates it from dark surfaces, the shadow from light ones.
                        .background(Brand.purpleFill, in: .capsule)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.2)) }
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityHint("Dismisses this message")
                .id(toast.id)
                .transition(reduceMotion ? .opacity
                            : .opacity.combined(with: .offset(y: edge == .top ? -Space.xs : Space.xs)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        .padding(Space.s)
        .animation(.snappy(duration: 0.2), value: store.toast?.id)
    }
}

/// Confirms a destructive action in place of the row it affects. Inline rather than a dialog: dialogs
/// attached to the menu-bar window can close it and lose the action. The row's title stays visible.
struct ConfirmRow: View {
    let question: String
    let detail: String
    let action: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: 32, height: 32)
                .background(.red.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(question).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button(action, role: .destructive, action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(.red.opacity(0.05))
        .accessibilityElement(children: .contain)
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
