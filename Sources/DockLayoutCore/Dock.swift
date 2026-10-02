import Foundation

/// Where layouts are read from and applied to. The real one talks to the
/// Dock's preferences; tests use an in-memory stand-in.
public protocol DockBackend {
    func readLayout() throws -> Layout
    func apply(_ layout: Layout) throws
}

#if os(macOS)
/// The live Dock, through CFPreferences (what `defaults` uses underneath).
public struct SystemDock: DockBackend {
    private static let domain = "com.apple.dock" as CFString

    public init() {}

    public func readLayout() throws -> Layout {
        // Drop any cached values so we see what the Dock has right now.
        CFPreferencesAppSynchronize(Self.domain)
        var layout: Layout = [:]
        for key in layoutKeys {
            guard let value = CFPreferencesCopyAppValue(key as CFString, Self.domain) else {
                layout[key] = [Any]()
                continue
            }
            guard let array = value as? [Any] else { throw DockLayoutError.notAList(key: key) }
            layout[key] = array
        }
        return layout
    }

    /// Replaces the two layout arrays, leaves every other Dock setting alone,
    /// then restarts the Dock so it picks them up.
    public func apply(_ layout: Layout) throws {
        for key in layoutKeys {
            let items = (layout[key] as? [Any]) ?? []
            CFPreferencesSetAppValue(key as CFString, NSArray(array: items), Self.domain)
        }
        guard CFPreferencesAppSynchronize(Self.domain) else { throw DockLayoutError.dockWriteFailed }
        try Self.restart()
    }

    private static var agent: String { "gui/\(getuid())/com.apple.Dock.agent" }

    /// Whether a Dock process is running for this user.
    public static var isRunning: Bool {
        run("/usr/bin/pgrep", ["-x", "-u", String(getuid()), "Dock"]) == 0
    }

    /// Restarts the Dock and waits until it's back.
    ///
    /// Don't just `killall Dock` and trust launchd to bring it back: after a few
    /// quick restarts it can leave the Dock down. `kickstart -k` has launchd stop
    /// and start it in one step, and we check that it came back. Because this
    /// waits, back-to-back switches can't pile kills onto a Dock still starting.
    public static func restart() throws {
        if run("/bin/launchctl", ["kickstart", "-k", agent]) != 0 {
            run("/usr/bin/killall", ["Dock"])
            // Let the old Dock exit, so the check below doesn't see it still running.
            Thread.sleep(forTimeInterval: 1)
        }
        if waitUntilRunning(seconds: 5) {
            return
        }
        // Still down: ask launchd to start it, without killing anything.
        run("/bin/launchctl", ["kickstart", agent])
        guard waitUntilRunning(seconds: 5) else { throw DockLayoutError.dockNotRunning }
    }

    private static func waitUntilRunning(seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if isRunning {
                // Give the new Dock a moment to finish starting before anything else touches it.
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
#endif

/// The operations the menu bar app and the CLI share.
public struct DockLayouts {
    public let store: LayoutStore
    public let dock: DockBackend

    public init(store: LayoutStore, dock: DockBackend) {
        self.store = store
        self.dock = dock
    }

    #if os(macOS)
    public static func system() -> DockLayouts {
        DockLayouts(store: LayoutStore(), dock: SystemDock())
    }
    #endif

    public func names() -> [String] { store.names() }

    public func liveLayout() throws -> Layout {
        let live = try dock.readLayout()
        return layoutKeys.reduce(into: Layout()) { $0[$1] = live[$1] ?? [Any]() }
    }

    /// The saved layout matching the Dock right now, if any.
    public func activeName() -> String? {
        guard let live = try? liveLayout() else { return nil }
        return store.name(matching: live)
    }

    public func save(_ name: String) throws {
        try store.write(try liveLayout(), as: name)
    }

    /// Backs up the current Dock, then switches to `name`.
    public func load(_ name: String) throws {
        let layout = try store.read(name)
        try store.backup(try liveLayout())
        try dock.apply(layout)
    }

    /// Restores the newest backup. Returns its timestamp name.
    /// The Dock being replaced is backed up first, so undo twice toggles back.
    @discardableResult
    public func undo() throws -> String {
        guard let previous = store.backups().last else { throw DockLayoutError.nothingToUndo }
        let layout = try store.readBackup(previous)
        try store.backup(try liveLayout())
        try dock.apply(layout)
        return previous.deletingPathExtension().lastPathComponent
    }

    public func delete(_ name: String) throws {
        try store.delete(name)
    }
}
