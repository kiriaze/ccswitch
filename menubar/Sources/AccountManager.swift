import Foundation
import Security

struct Account {
    let name: String
    let email: String
}

class AccountManager {
    static let shared = AccountManager()

    private let accountsDir: URL
    private let currentFile: URL
    private let claudeJSON: URL
    private let desktopConfig: URL
    private let desktopCookies: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        accountsDir    = home.appendingPathComponent(".claude-accounts")
        currentFile    = accountsDir.appendingPathComponent(".current")
        claudeJSON     = home.appendingPathComponent(".claude.json")
        desktopConfig  = home.appendingPathComponent("Library/Application Support/Claude/config.json")
        desktopCookies = home.appendingPathComponent("Library/Application Support/Claude/Cookies")
    }

    func loadAccounts() -> [Account] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: accountsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Account? in
                guard
                    let data  = try? Data(contentsOf: url),
                    let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let name  = obj["name"]  as? String,
                    let email = obj["email"] as? String
                else { return nil }
                return Account(name: name, email: email)
            }
            .sorted { $0.name < $1.name }
    }

    func currentAccountName() -> String? {
        try? String(contentsOf: currentFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Email from ~/.claude.json — may be stale if Claude desktop logged in a new user
    /// without the CLI having run yet. Exposed so the UI can let the user correct it.
    func liveEmail() -> String? {
        guard
            let data  = try? Data(contentsOf: claudeJSON),
            let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = obj["oauthAccount"] as? [String: Any],
            let email = oauth["emailAddress"] as? String,
            !email.isEmpty
        else { return nil }
        return email
    }

    /// True when the live tokenCache matches what's already saved for the current account.
    /// Compares tokenCache (updated by desktop login) not email (stale in ~/.claude.json).
    func isCurrentSessionSaved() -> Bool {
        guard
            let currentName = currentAccountName(),
            let configData  = try? Data(contentsOf: desktopConfig),
            let configObj   = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
            let liveCache   = configObj["oauth:tokenCache"] as? String,
            !liveCache.isEmpty,
            let savedData   = try? Data(contentsOf: accountFile(currentName)),
            let savedObj    = try? JSONSerialization.jsonObject(with: savedData) as? [String: Any],
            let savedCache  = savedObj["tokenCache"] as? String,
            !savedCache.isEmpty
        else { return false }
        return liveCache == savedCache
    }

    // MARK: - Mutations

    /// Snapshots the currently logged-in Claude session under `name`.
    /// `email` overrides what's in ~/.claude.json — useful when the desktop app hasn't
    /// flushed the new account's oauthAccount to disk yet.
    func saveCurrentAccount(name: String, email overrideEmail: String? = nil) throws {
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)

        guard
            let claudeData   = try? Data(contentsOf: claudeJSON),
            let claudeObj    = try? JSONSerialization.jsonObject(with: claudeData) as? [String: Any],
            let oauthAccount = claudeObj["oauthAccount"] as? [String: Any]
        else { throw CCSwitchError.notLoggedIn }

        let email = overrideEmail ?? oauthAccount["emailAddress"] as? String ?? "unknown"

        var tokenCache = ""
        if
            let configData = try? Data(contentsOf: desktopConfig),
            let configObj  = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        {
            tokenCache = configObj["oauth:tokenCache"] as? String ?? ""
        }

        // Capture the CLI's Keychain auth token — the actual Bearer token used for API
        // calls and billing. Without this, switching only changes the display name.
        let keychainCredentials = readKeychainCredentials() ?? ""

        let record: [String: Any] = [
            "name":                name,
            "email":               email,
            "oauthAccount":        oauthAccount,
            "tokenCache":          tokenCache,
            "keychainCredentials": keychainCredentials,
        ]
        let dest = accountFile(name)
        let data = try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted)
        try data.write(to: dest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)

        // Save desktop app Cookies — holds sessionKey that authenticates all desktop app
        // requests including billing. Without this, only CLI credential swaps work.
        if FileManager.default.fileExists(atPath: desktopCookies.path) {
            let cookiesDest = cookiesFile(name)
            try? FileManager.default.removeItem(at: cookiesDest)
            try FileManager.default.copyItem(at: desktopCookies, to: cookiesDest)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cookiesDest.path)
        }

        try writeCurrent(name)
    }

    /// Writes a saved account's credentials into the live Claude files.
    func applyAccount(name: String) throws {
        let src = accountFile(name)
        guard
            let data         = try? Data(contentsOf: src),
            let obj          = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauthAccount = obj["oauthAccount"] as? [String: Any]
        else { throw CCSwitchError.accountNotFound(name) }

        let tokenCache          = obj["tokenCache"]          as? String ?? ""
        let keychainCredentials = obj["keychainCredentials"] as? String ?? ""

        guard
            let claudeData = try? Data(contentsOf: claudeJSON),
            var claudeObj  = try? JSONSerialization.jsonObject(with: claudeData) as? [String: Any]
        else { throw CCSwitchError.notLoggedIn }

        claudeObj["oauthAccount"] = oauthAccount
        let newClaudeData = try JSONSerialization.data(withJSONObject: claudeObj, options: .prettyPrinted)
        try newClaudeData.write(to: claudeJSON, options: .atomic)

        if
            !tokenCache.isEmpty,
            let configData = try? Data(contentsOf: desktopConfig),
            var configObj  = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        {
            configObj["oauth:tokenCache"] = tokenCache
            let newConfigData = try JSONSerialization.data(withJSONObject: configObj, options: .prettyPrinted)
            try newConfigData.write(to: desktopConfig, options: .atomic)
        }

        // Restore CLI auth token in Keychain so the Claude Code CLI bills the right account.
        if !keychainCredentials.isEmpty {
            writeKeychainCredentials(keychainCredentials)
        }

        // Restore desktop app Cookies — sessionKey cookie authenticates all desktop app
        // requests including billing. Must be swapped for a complete session switch.
        let cookiesSrc = cookiesFile(name)
        if FileManager.default.fileExists(atPath: cookiesSrc.path) {
            try? FileManager.default.removeItem(at: desktopCookies)
            try FileManager.default.copyItem(at: cookiesSrc, to: desktopCookies)
            for ext in ["-journal", "-wal", "-shm"] {
                let stale = URL(fileURLWithPath: desktopCookies.path + ext)
                try? FileManager.default.removeItem(at: stale)
            }
        }

        try writeCurrent(name)
    }

    /// Renames a saved account. Does not touch live Claude files.
    func renameAccount(from oldName: String, to newName: String) throws {
        let src  = accountFile(oldName)
        let dest = accountFile(newName)

        guard
            let data = try? Data(contentsOf: src),
            var obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CCSwitchError.accountNotFound(oldName) }

        obj["name"] = newName
        let newData = try JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
        try newData.write(to: dest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        try FileManager.default.removeItem(at: src)

        if currentAccountName() == oldName {
            try writeCurrent(newName)
        }
    }

    /// Deletes a saved account profile. Does NOT affect the live Claude session.
    func removeAccount(name: String) throws {
        try FileManager.default.removeItem(at: accountFile(name))
        try? FileManager.default.removeItem(at: cookiesFile(name))
        if currentAccountName() == name {
            try? FileManager.default.removeItem(at: currentFile)
        }
    }

    // MARK: - Helpers

    private func accountFile(_ name: String) -> URL {
        accountsDir.appendingPathComponent("\(name).json")
    }

    private func cookiesFile(_ name: String) -> URL {
        accountsDir.appendingPathComponent("\(name).cookies")
    }

    private func writeCurrent(_ name: String) throws {
        try name.write(to: currentFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Keychain (CLI Bearer token)

    private let keychainService = "Claude Code-credentials"
    private var keychainAccount: String { NSUserName() }

    /// Reads the CLI's OAuth token from the macOS Keychain.
    /// This is the Bearer token the Claude Code CLI sends for all API calls.
    func readKeychainCredentials() -> String? {
        let query: [String: Any] = [
            kSecClass          as String: kSecClassGenericPassword,
            kSecAttrService    as String: keychainService,
            kSecAttrAccount    as String: keychainAccount,
            kSecReturnData     as String: true,
            kSecMatchLimit     as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes (creates or updates) the CLI's OAuth token in the macOS Keychain.
    func writeKeychainCredentials(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}

enum CCSwitchError: LocalizedError {
    case notLoggedIn
    case accountNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "No active Claude session found. Open Claude and log in first."
        case .accountNotFound(let name):
            return "Account '\(name)' not found."
        }
    }
}
