import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "ccswitch")
        }
        rebuildMenu()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu     = NSMenu()
        let accounts = AccountManager.shared.loadAccounts()
        let current  = AccountManager.shared.currentAccountName()

        if accounts.isEmpty {
            let empty = NSMenuItem(title: "No accounts saved", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for account in accounts {
                let title = "\(account.name)  \(account.email)"
                let item  = NSMenuItem(title: title, action: #selector(switchAccount(_:)), keyEquivalent: "")
                item.representedObject = account.name
                item.state  = account.name == current ? .on : .off
                item.target = self
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // "Save" is disabled when the live Claude session is already tracked
        let saveItem = NSMenuItem(title: "Save Current Account…", action: #selector(saveAccount), keyEquivalent: "")
        saveItem.target    = self
        saveItem.isEnabled = !AccountManager.shared.isCurrentSessionSaved()
        menu.addItem(saveItem)

        if !accounts.isEmpty {
            menu.addItem(withTitle: "Rename Account…", action: #selector(renameAccount), keyEquivalent: "")
                .target = self
            // Label clarifies this removes the saved profile, not the Claude login
            menu.addItem(withTitle: "Forget Account…", action: #selector(forgetAccount), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ccswitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func switchAccount(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }

        // No-op if already on this account
        if name == AccountManager.shared.currentAccountName() { return }

        ProcessManager.shared.quitClaude {
            DispatchQueue.main.async {
                do {
                    try AccountManager.shared.applyAccount(name: name)
                    self.rebuildMenu()
                    ProcessManager.shared.launchClaude()
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    @objc private func saveAccount() {
        let alert = NSAlert()
        alert.messageText     = "Save Current Account"
        alert.informativeText = "Enter a name for the currently logged-in Claude account."

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "e.g. personal, work"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            try AccountManager.shared.saveCurrentAccount(name: name)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func renameAccount() {
        let accounts = AccountManager.shared.loadAccounts()
        guard !accounts.isEmpty else { return }

        // Step 1: pick account to rename
        let pickAlert = NSAlert()
        pickAlert.messageText = "Rename Account"
        pickAlert.informativeText = "Choose the account to rename."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        for account in accounts { popup.addItem(withTitle: "\(account.name) (\(account.email))") }
        pickAlert.accessoryView = popup
        pickAlert.addButton(withTitle: "Next")
        pickAlert.addButton(withTitle: "Cancel")
        guard pickAlert.runModal() == .alertFirstButtonReturn else { return }

        let oldName = accounts[popup.indexOfSelectedItem].name

        // Step 2: enter new name
        let nameAlert = NSAlert()
        nameAlert.messageText     = "Rename \"\(oldName)\""
        nameAlert.informativeText = "Enter a new name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "new name"
        field.stringValue = oldName
        nameAlert.accessoryView = field
        nameAlert.addButton(withTitle: "Rename")
        nameAlert.addButton(withTitle: "Cancel")
        nameAlert.window.initialFirstResponder = field
        guard nameAlert.runModal() == .alertFirstButtonReturn else { return }

        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != oldName else { return }

        do {
            try AccountManager.shared.renameAccount(from: oldName, to: newName)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func forgetAccount() {
        let accounts = AccountManager.shared.loadAccounts()
        guard !accounts.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText     = "Forget Account"
        alert.informativeText = "Remove a saved account profile. This does not log you out of Claude."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        for account in accounts { popup.addItem(withTitle: "\(account.name) (\(account.email))") }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = accounts[popup.indexOfSelectedItem].name
        do {
            try AccountManager.shared.removeAccount(name: name)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    // MARK: - Helpers

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle      = .critical
        alert.messageText     = "ccswitch error"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }
}
