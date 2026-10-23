import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @AppStorage("globalShortcut") private var shortcut = HotKey.Preset.none
    @State private var shortcutTaken = false
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.time
    @AppStorage("menuBarSeconds") private var menuBarSeconds = false
    @AppStorage("menuBarHighlight") private var menuBarHighlight = true
    @AppStorage("rounding") private var rounding = Rounding.off
    @AppStorage("roundingStep") private var roundingStep = 15
    @AppStorage("idleEnabled") private var idleEnabled = true
    @AppStorage("idleMinutes") private var idleMinutes = 10
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("longTimerAlert") private var longTimerAlert = true
    @AppStorage("endOfDayNudge") private var endOfDayNudge = true
    @AppStorage("autoUpdate") private var autoUpdate = true
    private let updater = Updater.shared
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if SMAppService.mainApp.status == .requiresApproval {
                    Text("Allow Stint in System Settings › General › Login Items.").foregroundStyle(.secondary)
                }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            Section {
                Picker("Show", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Show seconds", isOn: $menuBarSeconds)
                    .disabled(menuBarStyle == .icon)
                Toggle("Highlight while running", isOn: $menuBarHighlight)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("The running timer always shows in the menu bar.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Start/Pause from any app", selection: $shortcut) {
                    ForEach(HotKey.Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: shortcut) { _, preset in
                    shortcutTaken = !HotKey.apply(preset) { Task { await store.pauseOrResume() } }
                }
                if shortcutTaken {
                    Label("Another app already uses \(shortcut.rawValue). Pick a different one.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Pauses the running timer, or resumes the last one.").foregroundStyle(.secondary)
            }
            Section {
                Picker("Rounding", selection: $rounding) {
                    ForEach(Rounding.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Step", selection: $roundingStep) {
                    ForEach(Rounding.steps, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .disabled(rounding == .off)
            } header: {
                Text("Time Logs")
            } footer: {
                Text("Applied when you log, and you can still edit the result. With 15 minutes, 1:13 rounds up to 1:15 or down to 1:00. Time is never rounded down to zero.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Working day", selection: Binding(get: { store.customDayLength != nil },
                                                         set: { store.customDayLength = $0 ? teamworkDays.max() ?? 8 * 3600 : nil })) {
                    Text(teamworkDays.isEmpty ? "From Teamwork" : "From Teamwork (\(teamworkDaySummary))").tag(false)
                    Text("Custom").tag(true)
                }
                if let custom = store.customDayLength {
                    Stepper("\(custom.hoursMinutes) a day", value: Binding(get: { custom }, set: { store.customDayLength = $0 }),
                            in: 900...86_400, step: 900)
                        .monospacedDigit()
                }
            } header: {
                Text("Targets")
            } footer: {
                Text("Sets the daily and weekly targets. Teamwork's come from your working hours in Edit My Details, or else your profile's day length.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Ask about idle time", isOn: $idleEnabled)
                Stepper("After \(idleMinutes) minutes without activity", value: $idleMinutes, in: 1...120)
                    .disabled(!idleEnabled)
            } header: {
                Text("Idle Time")
            } footer: {
                Text("Sleep counts as idle too. When you're back, keep the time or remove it and continue or stop.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Remind me when no timer is running", isOn: $remindersEnabled)
                Toggle("Alert when a timer runs over 8 hours", isOn: $longTimerAlert)
                Toggle("Remind me to log timers at the end of the day", isOn: $endOfDayNudge)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Reminders come every 30 minutes on weekdays, 9:00–17:00, after you last tracked time, until today's working hours are in. The end-of-day reminder comes once on weekdays from 17:00 if timers are left, with Log All.")
                    .foregroundStyle(.secondary)
            }
            .onChange(of: remindersEnabled || longTimerAlert || endOfDayNudge) { _, on in
                if on { Task { await Reminders.requestPermission() } }
            }
            Section {
                Toggle("Install updates automatically", isOn: $autoUpdate)
                LabeledContent("Stint \(Updater.current)") { updateStatus }
                if case .failed(let message) = updater.status {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(autoUpdate ? "Checks for a new version every few hours and installs it in the background. Stint restarts into it once you're away with no timer running."
                                : "Stint only checks when you click Check Now.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.status {
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Checking…") }
        case .installing(let version):
            HStack { ProgressView().controlSize(.small); Text("Installing \(version)…") }
        case .available(let version):
            HStack {
                Text("\(version) is available")
                Button("Install") { Task { await updater.install() } }
            }
        case .installed(let version):
            HStack {
                Text("\(version) is installed")
                Button("Restart Now") { updater.restart() }
            }
        case .idle, .upToDate, .failed:
            HStack {
                if updater.status == .upToDate { Text("Up to date") }
                Button("Check Now") { Task { await updater.check() } }
            }
        }
    }

    /// Teamwork's working-day lengths, one per working weekday.
    private var teamworkDays: [TimeInterval] {
        Array(workingDays(teamwork: store.teamworkHours, lengthOfDay: store.teamworkDayLength, custom: nil).values)
    }

    /// "7:30", or "6:00–7:30" when days differ.
    private var teamworkDaySummary: String {
        let (low, high) = (teamworkDays.min() ?? 0, teamworkDays.max() ?? 0)
        return low == high ? high.hoursMinutes : "\(low.hoursMinutes)–\(high.hoursMinutes)"
    }
}

struct AccountSettings: View {
    enum Method: String, CaseIterable, Identifiable {
        case token = "API Token"
        case oauth = "Your Own App"
        var id: Self { self }
    }

    @Environment(Store.self) private var store
    @AppStorage("signInMethod") private var method = Method.token
    @AppStorage("site") private var site = ""
    @AppStorage("oauthClientID") private var clientID = ""
    @AppStorage("oauthRedirect") private var redirect = "http://localhost:8123"
    @State private var token = ""
    /// Read from the Keychain only when the OAuth form shows: reading it on every draw asked for the
    /// login password whenever Account opened (once per build, as with any item; see `Keychain`).
    @State private var clientSecret = ""
    /// With a built-in app, the API token and own-app forms sit under Advanced.
    @State private var advanced = false
    @State private var signingIn: Task<Void, Never>?
    @State private var inBrowser = false
    @State private var error: String?

    private var busy: Bool { signingIn != nil }
    private var showsMethods: Bool { Launchpad.builtIn == nil || advanced }
    /// The built-in app signs in in Stint's own window, unless this build redirects to `appRedirect`.
    private var inWindow: Bool { Launchpad.builtIn?.redirect == teamworkRedirect }

    var body: some View {
        Form {
            if store.isSignedIn {
                Section {
                    LabeledContent("Site", value: store.site?.host() ?? "—")
                    LabeledContent("Signed in as", value: store.accountName ?? "—")
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        do { try store.signOut() } catch { self.error = error.localizedDescription }
                    }
                }
            } else {
                if Launchpad.builtIn != nil {
                    Section {
                        Button("Sign in with Teamwork") { run(inBrowser: !inWindow) { try await store.signInWithTeamwork() } }
                            .keyboardShortcut(advanced ? nil : .defaultAction)
                            // Filled default button: fixed purple keeps white text readable in Dark Mode. Once it's
                            // a plain button (Advanced open), its label is purple text, so use the adaptive tint.
                            .tint(advanced ? Brand.purple : Brand.purpleFill)
                            .disabled(busy)
                    } footer: {
                        Text(inWindow ? "Teamwork's sign-in page opens in a Stint window."
                                      : "Your browser opens Teamwork. Sign in there, then allow it to open Stint.")
                            .foregroundStyle(.secondary)
                    }
                    // A collapsible section, not a DisclosureGroup: in a grouped Form, a DisclosureGroup put the
                    // segmented picker in the "Advanced" row and clipped its top edge.
                    Section("Advanced", isExpanded: $advanced) {
                        methodPicker
                    }
                } else {
                    methodPicker
                }

                if showsMethods {
                    switch method {
                    case .token:
                        Section {
                            TextField("Site", text: $site, prompt: Text("acme.teamwork.com"))
                            SecureField("API token", text: $token)
                        } footer: {
                            Text("In Teamwork, open your profile, choose Edit My Details, then API & Mobile to copy your token. It's stored in your Keychain.")
                                .foregroundStyle(.secondary)
                        }
                        Button("Sign In") { run { try await store.signIn(site: site, token: token) } }
                            .keyboardShortcut(.defaultAction)
                            .tint(Brand.purpleFill)
                            .disabled(site.isEmpty || token.isEmpty || busy)
                    case .oauth:
                        Section {
                            TextField("Client ID", text: $clientID, prompt: Text("Required"))
                            SecureField("Client secret", text: $clientSecret, prompt: Text("Required"))
                            TextField("Redirect URI", text: $redirect)
                        } footer: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your own app needs registering for your site:")
                                Text("1. Open the Developer Portal and create an app.\n2. Add \(redirect) as a redirect URL (\(appRedirect.absoluteString) works too).\n3. Copy the Client ID and secret from its Credentials tab.")
                                Link("Open Developer Portal", destination: developerPortal)
                                    .foregroundStyle(.tint) // the footer's .secondary would draw it as plain text
                                Text("Just for yourself? An API token is quicker. The secret is stored in your Keychain.")
                            }
                            .foregroundStyle(.secondary)
                        }
                        Button("Sign In with Your App…") {
                            run(inBrowser: true) { try await store.signInWithOAuth(clientID: clientID, clientSecret: clientSecret, redirect: redirect) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .tint(Brand.purpleFill)
                        .disabled(clientID.isEmpty || clientSecret.isEmpty || busy)
                    }
                }

                if busy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(inBrowser ? "Waiting for the browser…" : "Signing in…").foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { signingIn?.cancel() }
                    }
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .task(id: showsMethods && method == .oauth) {
            if !store.isSignedIn, showsMethods, method == .oauth, clientSecret.isEmpty {
                do { clientSecret = try Store.savedOAuthSecret() ?? "" } catch { self.error = error.localizedDescription }
            }
        }
    }

    private var methodPicker: some View {
        Picker("Sign in with", selection: $method) {
            ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// Your site's portal (`<site>/developer`) once a site is known, else Teamwork's guide.
    private var developerPortal: URL {
        normalizedSite(site)?.appending(path: "developer")
            ?? URL(string: "https://apidocs.teamwork.com/guides/teamwork/create-an-app")!
    }

    private func run(inBrowser: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        error = nil
        self.inBrowser = inBrowser
        signingIn = Task {
            do { try await work() } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            signingIn = nil
        }
    }
}
