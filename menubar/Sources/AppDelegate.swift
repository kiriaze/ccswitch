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
        let detectedEmail = AccountManager.shared.liveEmail() ?? ""

        let alert = NSAlert()
        alert.messageText     = "Save Current Account"
        alert.informativeText = "Name this account. Correct the email if it looks wrong\n(Claude desktop may not update it until the CLI runs)."

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        stack.orientation = .vertical
        stack.spacing     = 8
        stack.alignment   = .left

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.placeholderString = "name (e.g. personal, work)"

        let emailField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        emailField.placeholderString = "email"
        emailField.stringValue = detectedEmail

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(emailField)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name  = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            try AccountManager.shared.saveCurrentAccount(name: name, email: email.isEmpty ? nil : email)
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
