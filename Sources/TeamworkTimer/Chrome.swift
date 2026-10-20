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
                    .buttonStyle(PressStyle())
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

/// The last error, and a calm status line while Teamwork's rate limit holds requests back.
struct ErrorBanner: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if store.rateLimited {
                Label(Store.rateLimitStatus, systemImage: "hourglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
            }
            error
        }
    }

    @ViewBuilder private var error: some View {
        if let error = store.errorMessage {
            HStack(alignment: .top) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { store.errorMessage = nil } label: {
                    Image(systemName: "xmark").frame(width: 22, height: 22).contentShape(.rect)
                }
                .buttonStyle(PressStyle())
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
                // In from its edge and a touch small (never from nothing); out as a quicker plain fade.
                .transition(.asymmetric(
                    insertion: reduceMotion ? .opacity
                        : .opacity.combined(with: .offset(y: edge == .top ? -Space.xs : Space.xs))
                            .combined(with: .scale(scale: 0.96, anchor: edge == .top ? .top : .bottom)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        .padding(Space.s)
        .animation(.snappy(duration: 0.22), value: store.toast?.id)
    }
}

/// For plain, borderless controls (header Back, week-strip days): dims and gives a little under
/// the pointer, so a click visibly lands. Native bordered buttons draw their own pressed state.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Pressed(configuration: configuration) }

    private struct Pressed: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: Configuration

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

extension View {
    /// Digits roll to a new value: a timer ticking over a minute, a total arriving. A crossfade under Reduce Motion.
    /// ponytail: only for values that change at most once a minute or on new data; a per-second clock would
    /// animate nonstop (see LiveDot), and totals that change on ← → day steps would animate a keyboard action.
    func rollingDigits(_ value: some Equatable) -> some View { modifier(RollingDigits(value: value)) }
}

private struct RollingDigits<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(.snappy(duration: 0.3), value: value)
    }
}

extension View {
    /// Rows fade in and out and glide into place when `ids` (in order) change: a timer logged or started (running
    /// timers sort first), a pin dropped in a new slot. Instant under Reduce Motion, where the glide is the motion.
    /// ponytail: main-window pages only. The popover resizes in one frame (StatusItem), which would clip a glide.
    func glidingRows(_ ids: some Equatable) -> some View { modifier(GlidingRows(ids: ids)) }
}

private struct GlidingRows<IDs: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ids: IDs

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .snappy(duration: 0.25), value: ids)
    }
}

/// Confirms an action in place of the row it affects. Inline rather than a dialog: dialogs
/// attached to the menu-bar window can close it and lose the action. The row's title stays visible.
struct ConfirmRow: View {
    let question: String
    let detail: String
    let action: String
    /// Red trash by default; a clock in brand purple otherwise.
    var destructive = true
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        let tint = destructive ? Color.red : Brand.purple
        HStack(spacing: Space.m) {
            Image(systemName: destructive ? "trash" : "clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(question).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button(action, role: destructive ? .destructive : nil, action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(destructive ? .red : Brand.purpleFill)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(tint.opacity(0.05))
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
