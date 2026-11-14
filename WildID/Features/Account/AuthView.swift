import SwiftUI

/// Sign in / create an account. Accounts live on this iPhone: no email, no verification code,
/// no second step. Creating an account signs you in immediately.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in", signUp = "Create account"
        var id: String { rawValue }
    }

    @Environment(AccountStore.self) private var accounts
    @State private var mode: Mode
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var error: String?
    @State private var busy = false
    @State private var showReset = false
    @FocusState private var focus: Field?
    enum Field { case username, name, password }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let wantsSignUp = args.firstIndex(of: "-wildid-auth").map { $0 + 1 < args.count && args[$0 + 1] == "signup" } ?? false
        _mode = State(initialValue: wantsSignUp ? .signUp : .signIn)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in error = nil }

                if mode == .signIn && !accounts.accounts.isEmpty { savedAccounts }

                VStack(spacing: 12) {
                    field(symbol: "person.fill") {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focus = mode == .signUp ? .name : .password }
                    }
                    if mode == .signUp {
                        field(symbol: "face.smiling") {
                            TextField("Display name (optional)", text: $displayName)
                                .textContentType(.nickname)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                    }
                    field(symbol: "lock.fill") {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    Text(mode == .signIn ? "Sign in" : "Create account & sign in").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || username.isEmpty || password.isEmpty)

                if mode == .signIn && !accounts.accounts.isEmpty {
                    Button("Forgot password?") { showReset = true }
                        .font(.subheadline.weight(.semibold))
                }

                Label("No email and no verification code: your account lives on this iPhone. Each account has its own Wild Index and Wildlings, and they come back if you reinstall WildID.",
                      systemImage: "lock.iphone")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showReset) { ResetPasswordView(prefill: username) }
        .onAppear {
            if mode == .signIn, accounts.accounts.count == 1 { username = accounts.accounts[0].username }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("WildMark").resizable().renderingMode(.template).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .frame(width: 84, height: 84)
                .background(LinearGradient(colors: [Theme.moss, Theme.mossDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Theme.moss.opacity(0.35), radius: 12, y: 6)
            Text("WildID").font(.system(size: 34, weight: .heavy, design: .rounded))
            Text(mode == .signIn ? "Welcome back, explorer." : "Start your own Wild Index.")
                .font(.title3).foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 20)
    }

    private var savedAccounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ON THIS IPHONE").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(accounts.accounts) { a in
                        Button {
                            username = a.username
                            focus = .password
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(a.greetingName.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Theme.moss, in: Circle())
                                Text(a.username).font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 5)
                            .background(username.lowercased() == a.username.lowercased() ? Theme.moss.opacity(0.18) : Theme.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func field<C: View>(symbol: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.moss).frame(width: 22)
            content()
        }
        .font(.system(size: 17))
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if mode == .signIn {
                try accounts.signIn(username: username, password: password)
            } else {
                try accounts.signUp(username: username, password: password, displayName: displayName)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// New password for an account on this iPhone, confirmed with Face ID / Touch ID / passcode
/// (there is no email to send a reset link to).
struct ResetPasswordView: View {
    var prefill: String
    @Environment(AccountStore.self) private var accounts
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var newPassword = ""
    @State private var message: String?
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("New password (6+ characters)", text: $newPassword)
                        .textContentType(.newPassword)
                } footer: {
                    Text("To prove it's your iPhone, WildID asks for Face ID, Touch ID or your passcode. Your Wild Index is kept.")
                }
                if let message {
                    Text(message).foregroundStyle(done ? Theme.moss : Theme.ember)
                }
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") { Task { await reset() } }.disabled(username.isEmpty || newPassword.count < 6 || done)
                }
            }
            .onAppear { username = prefill }
        }
    }

    private func reset() async {
        guard await AccountStore.confirmDeviceOwner(reason: "Reset the WildID password for \(username)") else {
            message = "Couldn't confirm it's you."
            return
        }
        do {
            try accounts.resetPassword(username: username, newPassword: newPassword)
            done = true
            message = "Password changed. You can sign in now."
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
