import AppKit
import DockLayoutCore
import ServiceManagement

enum Dialogs {
    /// Asks for a layout name until it's valid or the user cancels.
    static func askName() -> String? {
        var message = "Name this Dock. Use letters, numbers, dots, underscores, or hyphens."
        var suggestion = ""
        while true {
            let alert = makeAlert("Save Dock layout", body: message)
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.placeholderString = "Work"
            field.stringValue = suggestion
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { return nil }
            if LayoutStore.isValidName(name) { return name }
            suggestion = name
            message = "\"\(name)\" can't be used. Use letters, numbers, dots, underscores, or hyphens, "
                + "starting with a letter or number (64 characters max)."
        }
    }

    static func confirm(_ title: String, body: String, button: String) -> Bool {
        let alert = makeAlert(title, body: body)
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func inform(_ title: String, body: String) {
        let alert = makeAlert(title, body: body.trimmingCharacters(in: .whitespacesAndNewlines))
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func makeAlert(_ title: String, body: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.window.level = .floating
        // A menu bar app isn't frontmost; bring the alert forward.
        NSApp.activate(ignoringOtherApps: true)
        return alert
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Symlinks `~/.local/bin/docklayout` to the CLI inside this app bundle,
/// so the terminal command updates whenever the app does.
enum CommandLineTool {
    static var bundled: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/docklayout")
    }

    static var link: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/docklayout")
    }

    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == bundled.path
    }

    @discardableResult
    static func install() throws -> URL {
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: bundled.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: bundled.path])
        }
        try manager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Replace an older symlink (such as the npx install's), never a real file.
        if (try? manager.destinationOfSymbolicLink(atPath: link.path)) != nil {
            try manager.removeItem(at: link)
        } else if manager.fileExists(atPath: link.path) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: link.path])
        }
        try manager.createSymbolicLink(at: link, withDestinationURL: bundled)
        return link
    }
}

/// Cleans up after the npx-installed version (0.2 and earlier).
enum Migration {
    private static let legacyLabel = "com.nicolaswebdev.docklayout"

    /// Quits an older copy of the app running from another location.
    /// Returns false if this same app is already running, so this launch should quit.
    static func takeOverFromOtherInstances() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
        if others.contains(where: { $0.bundleURL?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL }) {
            return false
        }
        for other in others {
            other.terminate()
        }
        return true
    }

    static func run() {
        // Opened straight from the DMG or a quarantined download: Gatekeeper runs a
        // temporary copy. Wait until the app runs from where it will stay.
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agent = home.appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist")
        let defaults = UserDefaults.standard
        let firstLaunch = !defaults.bool(forKey: "launchedBefore")
        defaults.set(true, forKey: "launchedBefore")

        let hadLegacyAgent = FileManager.default.fileExists(atPath: agent.path)
        if hadLegacyAgent {
            try? FileManager.default.removeItem(at: agent)
            // The old npx install, the Python CLI it shipped, and its PATH link.
            let legacySupport = home.appendingPathComponent("Library/Application Support/docklayout")
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: CommandLineTool.link.path),
               target.hasPrefix(legacySupport.path) {
                try? CommandLineTool.install()
            }
            try? FileManager.default.removeItem(at: legacySupport)
        }

        // Start at Login was on by default before; keep that for upgrades and fresh installs.
        if firstLaunch || hadLegacyAgent, !LoginItem.isEnabled {
            try? LoginItem.setEnabled(true)
        }
    }
}
