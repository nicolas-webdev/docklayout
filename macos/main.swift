import AppKit
import Foundation

private let agentLabel = "com.nicolaswebdev.docklayout"

private struct CommandResult {
    var code: Int32
    var out: String
    var err: String
}

private func cliPath() -> String {
    if let env = ProcessInfo.processInfo.environment["DOCKLAYOUT_BIN"], !env.isEmpty {
        return env
    }
    let local = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/docklayout").path
    if FileManager.default.isExecutableFile(atPath: local) {
        return local
    }
    return local
}

private func run(_ args: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cliPath())
    process.arguments = args
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    do {
        try process.run()
    } catch {
        return CommandResult(code: 1, out: "", err: error.localizedDescription)
    }
    process.waitUntilExit()
    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return CommandResult(code: process.terminationStatus, out: out, err: err)
}

private func layoutNames() -> [String] {
    let result = run(["list"])
    guard result.code == 0 else { return [] }
    return result.out
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("No Dock") }
}

private func activeName() -> String {
    run(["active"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func layoutDirectory() -> URL {
    if let override = ProcessInfo.processInfo.environment["DOCKLAYOUT_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            .appendingPathComponent("layouts")
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/docklayout/layouts")
}

private func agentURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
}

private func launchAgentPlist(executable: String, cli: String) -> Data {
    let plist: [String: Any] = [
        "Label": agentLabel,
        "ProgramArguments": [executable],
        "RunAtLoad": true,
        "EnvironmentVariables": ["DOCKLAYOUT_BIN": cli],
    ]
    return try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
}

private func dockIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.set()
        let bar = NSBezierPath(
            roundedRect: NSRect(x: 1, y: 2.5, width: 16, height: 6),
            xRadius: 1.6,
            yRadius: 1.6
        )
        bar.lineWidth = 1.3
        bar.stroke()
        for index in 0..<4 {
            let x = 2.6 + CGFloat(index) * 3.7
            NSBezierPath(rect: NSRect(x: x, y: 4.1, width: 2.2, height: 2.8)).fill()
        }
        return true
    }
    image.isTemplate = true
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--debug-menu") {
            let active = activeName()
            let names = layoutNames()
            if names.isEmpty {
                print("(none)")
            }
            for name in names {
                print(name == active ? "* \(name)" : "  \(name)")
            }
            NSApp.terminate(nil)
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? agentLabel
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = dockIcon()
            button.setAccessibilityLabel("Dock Layout")
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let names = layoutNames()
        let active = activeName()

        if names.isEmpty {
            let empty = NSMenuItem(title: "No layouts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for name in names {
                let item = NSMenuItem(title: name, action: #selector(loadLayout(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                item.state = name == active ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let save = NSMenuItem(title: "Save Current Dock…", action: #selector(saveLayout), keyEquivalent: "")
        save.target = self
        menu.addItem(save)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = FileManager.default.fileExists(atPath: agentURL().path) ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Dock Layout", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func loadLayout(_ sender: NSMenuItem) {
        guard !busy, let name = sender.representedObject as? String else { return }
        busy = true
        let result = run(["load", name])
        busy = false
        if result.code != 0 {
            showAlert(title: "Couldn't switch to \(name)", body: result.err)
        }
    }

    @objc private func saveLayout() {
        guard !busy else { return }
        let name = askName()
        guard !name.isEmpty else { return }
        let file = layoutDirectory().appendingPathComponent("\(name).plist")
        if FileManager.default.fileExists(atPath: file.path), !confirmReplace(name) {
            return
        }
        busy = true
        let result = run(["save", name])
        busy = false
        if result.code != 0 {
            showAlert(title: "Couldn't save \(name)", body: result.err)
        }
    }

    @objc private func toggleLogin() {
        let url = agentURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let executable = Bundle.main.executableURL?.path else { return }
        let data = launchAgentPlist(executable: executable, cli: cliPath())
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func askName() -> String {
        let alert = NSAlert()
        alert.messageText = "Save Dock layout"
        alert.informativeText = "Name this Dock. Use letters, numbers, dots, underscores, or hyphens."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Work"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return "" }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func confirmReplace(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace \(name)?"
        alert.informativeText = "This overwrites the saved Dock named \(name)."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private let appDelegate = AppDelegate()

@main
enum DockLayoutMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}
