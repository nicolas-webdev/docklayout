import AppKit
import DockLayoutCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let layouts = DockLayouts.system()
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

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
        item.menu = menu
        statusItem = item
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        if !SystemDock.isRunning {
            menu.addItem(menuItem("The Dock isn't running. Restart It", #selector(restartDock)))
            menu.addItem(.separator())
        }
        let names = layouts.names()
        let active = layouts.activeName()

        if names.isEmpty {
            let empty = NSMenuItem(title: "No layouts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for name in names {
            let item = menuItem(name, #selector(loadLayout(_:)))
            item.representedObject = name
            item.state = name == active ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Save Current Dock…", #selector(saveLayout)))
        let undo = menuItem("Undo Last Switch", #selector(undoSwitch))
        undo.isEnabled = !layouts.store.backups().isEmpty
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

    // MARK: Actions

    @objc private func loadLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        attempt("Couldn't switch to \(name)") { try layouts.load(name) }
    }

    @objc private func saveLayout() {
        guard let name = Dialogs.askName() else { return }
        if layouts.store.exists(name), !Dialogs.confirm(
            "Replace \(name)?",
            body: "This overwrites the saved Dock named \(name).",
            button: "Replace"
        ) {
            return
        }
        attempt("Couldn't save \(name)") { try layouts.save(name) }
    }

    @objc private func restartDock() {
        attempt("Couldn't restart the Dock") { try SystemDock.restart() }
    }

    @objc private func undoSwitch() {
        attempt("Couldn't undo") { try layouts.undo() }
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
