import AppKit
import DockLayoutCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let layouts = DockLayouts.system()
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    /// Switching restarts the Dock and waits for it, which can take seconds,
    /// so it runs here instead of freezing the menu bar.
    private let dockQueue = DispatchQueue(label: "com.nicolaswebdev.docklayout.dock")
    private var busy = false {
        didSet { statusItem?.button?.appearsDisabled = busy }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--debug-menu") {
            printDebugMenu()
            NSApp.terminate(nil)
            return
        }
        guard Migration.takeOverFromOtherInstances() else {
            NSApp.terminate(nil)
            return
        }
        Migration.run()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        item.button?.setAccessibilityLabel("Dock Layout")
        menu.delegate = self
        // We set isEnabled ourselves; NSMenu would otherwise re-enable every item.
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        if busy {
            menu.addItem(disabledItem("Switching the Dock…"))
            menu.addItem(.separator())
        } else if !SystemDock.isRunning {
            menu.addItem(menuItem("The Dock isn't running. Restart It", #selector(restartDock)))
            menu.addItem(.separator())
        }
        let names = layouts.names()
        // Mid-switch the Dock is restarting; no check mark beats a wrong one.
        let active = busy ? nil : layouts.activeName()

        if names.isEmpty {
            menu.addItem(disabledItem("No layouts yet"))
        }
        for name in names {
            let item = menuItem(name, #selector(loadLayout(_:)))
            item.representedObject = name
            item.state = name == active ? .on : .off
            item.isEnabled = !busy
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let save = menuItem("Save Current Dock…", #selector(saveLayout))
        save.isEnabled = !busy
        menu.addItem(save)
        let undo = menuItem("Undo Last Switch", #selector(undoSwitch))
        undo.isEnabled = !busy && !layouts.store.backups().isEmpty
        menu.addItem(undo)
        if !names.isEmpty {
            let delete = NSMenuItem(title: "Delete Layout", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for name in names {
                let item = menuItem(name, #selector(deleteLayout(_:)))
                item.representedObject = name
                submenu.addItem(item)
            }
            delete.submenu = submenu
            menu.addItem(delete)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Open Layouts Folder", #selector(openLayoutsFolder)))
        let cli = menuItem("Install Command Line Tool…", #selector(installCommandLineTool))
        cli.state = CommandLineTool.isInstalled ? .on : .off
        menu.addItem(cli)
        let login = menuItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Dock Layout", #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func loadLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        inBackground("Couldn't switch to \(name)") { try $0.load(name) }
    }

    @objc private func saveLayout() {
        guard !busy, let typed = Dialogs.askName() else { return }
        // "work" and "Work" are the same file on a normal macOS disk, so offer
        // to replace the existing layout under its own spelling.
        var name = typed
        if let existing = layouts.store.existingName(matching: typed) {
            guard Dialogs.confirm(
                "Replace \(existing)?",
                body: "This overwrites the saved Dock named \(existing).",
                button: "Replace"
            ) else { return }
            name = existing
        }
        inBackground("Couldn't save \(name)") { try $0.save(name) }
    }

    @objc private func restartDock() {
        inBackground("Couldn't restart the Dock") { try $0.restartDock() }
    }

    @objc private func undoSwitch() {
        inBackground("Couldn't undo") { _ = try $0.undo() }
    }

    @objc private func deleteLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              Dialogs.confirm("Delete \(name)?", body: "The saved Dock named \(name) will be removed.", button: "Delete")
        else { return }
        attempt("Couldn't delete \(name)") { try layouts.delete(name) }
    }

    @objc private func openLayoutsFolder() {
        let folder = layouts.store.layoutsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func installCommandLineTool() {
        do {
            let link = try CommandLineTool.install()
            Dialogs.inform(
                "Command line tool installed",
                body: "\(link.path) now points to this app.\n\n"
                    + "If your shell can't find docklayout, add this to ~/.zshrc:\n"
                    + "export PATH=\"$HOME/.local/bin:$PATH\""
            )
        } catch {
            Dialogs.inform("Couldn't install the command line tool", body: error.localizedDescription)
        }
    }

    @objc private func toggleLogin() {
        attempt("Couldn't change Start at Login") { try LoginItem.setEnabled(!LoginItem.isEnabled) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Runs a Dock change off the main thread, one at a time, and reports
    /// any error back on the main thread.
    private func inBackground(_ title: String, _ work: @escaping (DockLayouts) throws -> Void) {
        guard !busy else { return }
        busy = true
        let layouts = self.layouts
        dockQueue.async {
            var failure: Error?
            do {
                try work(layouts)
            } catch {
                failure = error
            }
            DispatchQueue.main.async {
                self.busy = false
                if let failure {
                    Dialogs.inform(title, body: failure.localizedDescription)
                }
            }
        }
    }

    private func attempt(_ title: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            Dialogs.inform(title, body: error.localizedDescription)
        }
    }

    private func printDebugMenu() {
        let active = layouts.activeName()
        let names = layouts.names()
        if names.isEmpty {
            print("(none)")
        }
        for name in names {
            print(name == active ? "* \(name)" : "  \(name)")
        }
    }
}
