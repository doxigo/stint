import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Account", systemImage: "person.crop.circle") { AccountSettings() }
        }
        .frame(width: 480)
    }
}

struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @AppStorage("globalShortcut") private var shortcut = HotKey.Preset.none
    @State private var shortcutTaken = false
    @AppStorage("miniTimer") private var miniTimer = false
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.time
    @AppStorage("menuBarSeconds") private var menuBarSeconds = false
    @AppStorage("rounding") private var rounding = Rounding.off
    @AppStorage("roundingStep") private var roundingStep = 15
    @AppStorage("idleEnabled") private var idleEnabled = true
    @AppStorage("idleMinutes") private var idleMinutes = 10
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("longTimerAlert") private var longTimerAlert = true
    @AppStorage("endOfDayNudge") private var endOfDayNudge = true
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
                    Text("Allow Teamwork Timer in System Settings › General › Login Items.").foregroundStyle(.secondary)
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
                Toggle("Floating mini timer", isOn: $miniTimer)
                    .onChange(of: miniTimer) { _, shown in MiniTimer.setShown(shown, store: store) }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("The running timer always shows in the menu bar. The floating mini timer is an extra window above other apps (⇧⌘M).")
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
                Text("Reminders come every 30 minutes on weekdays, 9:00–17:00, after you last tracked time. The end-of-day reminder comes once on weekdays from 17:00 if timers are left, with Log All.")
                    .foregroundStyle(.secondary)
            }
            .onChange(of: remindersEnabled || longTimerAlert || endOfDayNudge) { _, on in
                if on { Task { await Reminders.requestPermission() } }
            }
        }
        .formStyle(.grouped)
    }
}

struct AccountSettings: View {
    enum Method: String, CaseIterable, Identifiable {
        case token = "API Token"
        case oauth = "Teamwork Sign-In"
        var id: Self { self }
    }

    @Environment(Store.self) private var store
    @AppStorage("signInMethod") private var method = Method.token
    @AppStorage("site") private var site = ""
    @AppStorage("oauthClientID") private var clientID = ""
    @AppStorage("oauthRedirect") private var redirect = "http://localhost:8123"
    @State private var token = ""
    @State private var clientSecret = Store.savedOAuthSecret ?? ""
    @State private var signingIn: Task<Void, Never>?
    @State private var error: String?

    private var busy: Bool { signingIn != nil }

    var body: some View {
        Form {
            if store.isSignedIn {
                Section {
                    LabeledContent("Site", value: store.site?.host() ?? "—")
                    LabeledContent("Signed in as", value: store.accountName ?? "—")
                }
                Section {
                    Button("Sign Out", role: .destructive) { store.signOut() }
                }
            } else {
                Picker("Sign in with", selection: $method) {
                    ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

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
                        .tint(Brand.purpleFill) // filled default button: fixed purple keeps white text readable in Dark Mode
                        .disabled(site.isEmpty || token.isEmpty || busy)
                case .oauth:
                    Section {
                        TextField("Client ID", text: $clientID, prompt: Text("Required"))
                        SecureField("Client secret", text: $clientSecret, prompt: Text("Required"))
                        TextField("Redirect URI", text: $redirect)
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Teamwork Sign-In needs an app registered for your site:")
                            Text("1. Open the Developer Portal and create an app.\n2. Add \(redirect) as a redirect URL.\n3. Copy the Client ID and secret from its Credentials tab.")
                            Link("Open Developer Portal", destination: developerPortal)
                            Text("Just for yourself? An API token is quicker. The secret is stored in your Keychain.")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button("Sign In with Teamwork…") {
                        run { try await store.signInWithOAuth(clientID: clientID, clientSecret: clientSecret, redirect: redirect) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(Brand.purpleFill) // filled default button: fixed purple keeps white text readable in Dark Mode
                    .disabled(clientID.isEmpty || clientSecret.isEmpty || busy)
                }

                if busy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(method == .oauth ? "Waiting for the browser…" : "Signing in…").foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { signingIn?.cancel() }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Your site's portal (`<site>/developer`) once a site is known, else Teamwork's guide.
    private var developerPortal: URL {
        normalizedSite(site)?.appending(path: "developer")
            ?? URL(string: "https://apidocs.teamwork.com/guides/teamwork/create-an-app")!
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        error = nil
        signingIn = Task {
            do { try await work() } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            signingIn = nil
        }
    }
}
