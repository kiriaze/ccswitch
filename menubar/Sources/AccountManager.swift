import Foundation

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

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        accountsDir  = home.appendingPathComponent(".claude-accounts")
        currentFile  = accountsDir.appendingPathComponent(".current")
        claudeJSON   = home.appendingPathComponent(".claude.json")
        desktopConfig = home
            .appendingPathComponent("Library/Application Support/Claude/config.json")
    }

    func loadAccounts() -> [Account] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: accountsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Account? in
                guard
                    let data = try? Data(contentsOf: url),
                    let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let name  = obj["name"]  as? String,
                    let email = obj["email"] as? String
                else { return nil }
                return Account(name: name, email: email)
            }
            .sorted { $0.name < $1.name }
    }

    func currentAccountName() -> String? {
        try? String(contentsOf: currentFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Saves the currently logged-in account under `name`.
    func saveCurrentAccount(name: String) throws {
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)

        guard
            let claudeData = try? Data(contentsOf: claudeJSON),
            let claudeObj  = try? JSONSerialization.jsonObject(with: claudeData) as? [String: Any],
            let oauthAccount = claudeObj["oauthAccount"] as? [String: Any]
        else {
            throw CCSwitchError.notLoggedIn
        }
        let email = oauthAccount["emailAddress"] as? String ?? "unknown"

        var tokenCache = ""
        if
            let configData = try? Data(contentsOf: desktopConfig),
            let configObj  = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        {
            tokenCache = configObj["oauth:tokenCache"] as? String ?? ""
        }

        let record: [String: Any] = [
            "name":         name,
            "email":        email,
            "oauthAccount": oauthAccount,
            "tokenCache":   tokenCache,
        ]
        let dest = accountsDir.appendingPathComponent("\(name).json")
        let data = try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted)
        try data.write(to: dest, options: .atomic)
        try setPermissions(url: dest, octal: 0o600)
        try currentAccountName(name)
    }

    // Writes target account credentials into the active Claude files.
    func applyAccount(name: String) throws {
        let src = accountsDir.appendingPathComponent("\(name).json")
        guard
            let data = try? Data(contentsOf: src),
            let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauthAccount = obj["oauthAccount"] as? [String: Any]
        else {
            throw CCSwitchError.accountNotFound(name)
        }
        let tokenCache = obj["tokenCache"] as? String ?? ""

        // Patch ~/.claude.json
        guard
            let claudeData = try? Data(contentsOf: claudeJSON),
            var claudeObj  = try? JSONSerialization.jsonObject(with: claudeData) as? [String: Any]
        else {
            throw CCSwitchError.notLoggedIn
        }
        claudeObj["oauthAccount"] = oauthAccount
        let newClaudeData = try JSONSerialization.data(withJSONObject: claudeObj, options: .prettyPrinted)
        try newClaudeData.write(to: claudeJSON, options: .atomic)

        // Patch desktop config
        if
            !tokenCache.isEmpty,
            let configData = try? Data(contentsOf: desktopConfig),
            var configObj  = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        {
            configObj["oauth:tokenCache"] = tokenCache
            let newConfigData = try JSONSerialization.data(withJSONObject: configObj, options: .prettyPrinted)
            try newConfigData.write(to: desktopConfig, options: .atomic)
        }

        try currentAccountName(name)
    }

    func removeAccount(name: String) throws {
        let file = accountsDir.appendingPathComponent("\(name).json")
        try FileManager.default.removeItem(at: file)
        if currentAccountName() == name {
            try? FileManager.default.removeItem(at: currentFile)
        }
    }

    private func currentAccountName(_ name: String) throws {
        try name.write(to: currentFile, atomically: true, encoding: .utf8)
    }

    private func setPermissions(url: URL, octal: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: octal], ofItemAtPath: url.path)
    }
}

enum CCSwitchError: LocalizedError {
    case notLoggedIn
    case accountNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "No active Claude session found. Log in to Claude first."
        case .accountNotFound(let name):
            return "Account '\(name)' not found."
        }
    }
}
