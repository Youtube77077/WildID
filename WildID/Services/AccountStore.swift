import CommonCrypto
import Foundation
import LocalAuthentication
import Security
import SwiftData

/// A WildID account. Accounts live on this iPhone only: there is no server, no email and no
/// verification step. Signing up logs you in straight away.
struct Account: Codable, Identifiable, Equatable {
    var id: UUID
    var username: String
    var displayName: String
    var createdAt: Date
    var salt: Data
    var passwordHash: Data
    /// SwiftData store file and Keychain backup used by this account's Wild Index.
    var storeName: String
    var backupService: String

    var greetingName: String { displayName.isEmpty ? username : displayName }
}

/// Where the account list is kept. The app uses the Keychain (device-only); tests use memory.
protocol AccountVault {
    func load() -> Data?
    func save(_ data: Data)
}

/// Keychain storage, "this device only" and never synced: it survives deleting the app, like the
/// Wild Index backup, and never leaves this iPhone.
struct KeychainAccountVault: AccountVault {
    var service = "wildid.accounts.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "accounts"]
    }
    func load() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    func save(_ data: Data) {
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = query
            attrs.forEach { add[$0.key] = $0.value }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

final class MemoryAccountVault: AccountVault {
    var data: Data?
    init() {}
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}

/// Everything that belongs to the signed-in account: its own database and app environment.
/// Created once per sign-in, so switching accounts swaps the whole Wild Index.
@MainActor
final class AccountSession: Identifiable {
    let account: Account
    let container: ModelContainer
    let env: AppEnvironment
    var id: UUID { account.id }

    init(account: Account, inMemory: Bool) {
        self.account = account
        let schema = Schema([WildIndexEntry.self, Catch.self, SavedRecording.self, RecordingDetection.self])
        let config = inMemory ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration(account.storeName, schema: schema)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        BackupStore.shared.use(service: account.backupService)
        env = AppEnvironment(container: container)
    }
}

@MainActor
@Observable
final class AccountStore {
    enum AuthError: LocalizedError, Equatable {
        case usernameInvalid, usernameTaken, passwordTooShort, wrongCredentials, unknownUser
        var errorDescription: String? {
            switch self {
            case .usernameInvalid: "Usernames are 3–20 letters, numbers, dots or underscores."
            case .usernameTaken: "That username is already used on this iPhone."
            case .passwordTooShort: "Use at least 6 characters for your password."
            case .wrongCredentials: "Wrong username or password."
            case .unknownUser: "There's no account with that username on this iPhone."
            }
        }
    }

    private(set) var accounts: [Account] = []
    private(set) var session: AccountSession?
    private let vault: AccountVault
    private let defaults: UserDefaults
    private let inMemoryStores: Bool
    private static let currentKey = "currentAccountID"
    static let rounds: UInt32 = 120_000

    init(vault: AccountVault = KeychainAccountVault(), defaults: UserDefaults = .standard, inMemoryStores: Bool = false) {
        self.vault = vault
        self.defaults = defaults
        self.inMemoryStores = inMemoryStores
        if let data = vault.load(), let list = try? JSONDecoder().decode([Account].self, from: data) { accounts = list }
    }

    var current: Account? { session?.account }

    /// Restores the last signed-in account. The choice is kept in UserDefaults, which iOS deletes
    /// with the app, so after a reinstall you sign in again and your Wild Index comes back.
    func restoreSession() {
        guard session == nil, let raw = defaults.string(forKey: Self.currentKey), let id = UUID(uuidString: raw),
              let account = accounts.first(where: { $0.id == id }) else { return }
        start(account)
    }

    /// Creates an account and signs in immediately (no email, no verification, no second step).
    @discardableResult
    func signUp(username rawUsername: String, password: String, displayName: String = "") throws -> Account {
        let username = rawUsername.trimmingCharacters(in: .whitespaces)
        guard Self.isValid(username: username) else { throw AuthError.usernameInvalid }
        guard !accounts.contains(where: { $0.username.lowercased() == username.lowercased() }) else { throw AuthError.usernameTaken }
        guard password.count >= 6 else { throw AuthError.passwordTooShort }
        let id = UUID()
        let salt = Self.randomSalt()
        // The first account on this iPhone keeps the Wild Index that was collected before accounts existed.
        let first = accounts.isEmpty
        let account = Account(id: id, username: username,
                              displayName: displayName.trimmingCharacters(in: .whitespaces).prefix(30).description,
                              createdAt: Date(), salt: salt, passwordHash: Self.hash(password, salt: salt),
                              storeName: first ? "WildID" : "WildID-\(id.uuidString)",
                              backupService: first ? "wildid.backup.v1" : "wildid.backup.v1.\(id.uuidString)")
        accounts.append(account)
        persist()
        start(account)
        return account
    }

    func signIn(username: String, password: String) throws {
        guard let account = accounts.first(where: { $0.username.lowercased() == username.trimmingCharacters(in: .whitespaces).lowercased() }),
              Self.constantTimeEqual(Self.hash(password, salt: account.salt), account.passwordHash) else {
            throw AuthError.wrongCredentials
        }
        start(account)
    }

    func signOut() {
        if session?.env.sound.isActive == true { session?.env.sound.stop() }
        session = nil
        defaults.removeObject(forKey: Self.currentKey)
    }

    /// Sets a new password after the iPhone owner confirmed with Face ID, Touch ID or passcode.
    func resetPassword(username: String, newPassword: String) throws {
        guard let i = accounts.firstIndex(where: { $0.username.lowercased() == username.trimmingCharacters(in: .whitespaces).lowercased() }) else {
            throw AuthError.unknownUser
        }
        guard newPassword.count >= 6 else { throw AuthError.passwordTooShort }
        let salt = Self.randomSalt()
        accounts[i].salt = salt
        accounts[i].passwordHash = Self.hash(newPassword, salt: salt)
        persist()
    }

    func updateDisplayName(_ name: String) {
        guard let id = current?.id, let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].displayName = String(name.trimmingCharacters(in: .whitespaces).prefix(30))
        persist()
    }

    /// Asks for Face ID / Touch ID / the iPhone passcode. If the phone has no passcode at all,
    /// anyone holding it could open WildID anyway, so the reset is allowed.
    static func confirmDeviceOwner(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// For CI screenshots: a throwaway signed-in account with an in-memory store.
    func startDemoSession() {
        let account = Account(id: UUID(), username: "explorer", displayName: "Explorer", createdAt: Date(),
                              salt: Data(), passwordHash: Data(), storeName: "demo", backupService: "wildid.backup.demo")
        session = AccountSession(account: account, inMemory: true)
    }

    // MARK: Internals

    private func start(_ account: Account) {
        session = AccountSession(account: account, inMemory: inMemoryStores)
        defaults.set(account.id.uuidString, forKey: Self.currentKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) { vault.save(data) }
    }

    static func isValid(username: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        return (3...20).contains(username.count) && username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// PBKDF2-HMAC-SHA256: the password itself is never stored.
    static func hash(_ password: String, salt: Data) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8).map { CChar(bitPattern: $0) }
        let saltBytes = [UInt8](salt)
        _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passwordBytes.count,
                                 saltBytes, saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                 rounds, &derived, derived.count)
        return Data(derived)
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}
