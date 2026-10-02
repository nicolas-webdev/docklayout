import Foundation

/// The two Dock preference arrays a layout holds. Size, autohide,
/// magnification and hot corners live in other keys and are never touched.
public let layoutKeys = ["persistent-apps", "persistent-others"]

/// A snapshot of `persistent-apps` and `persistent-others`, exactly as the
/// Dock stores them. Tile bookmark data is kept as-is.
public typealias Layout = [String: Any]

public enum DockLayoutError: LocalizedError, Equatable {
    case invalidName(String)
    case nameTaken(existing: String)
    case notFound(String)
    case nothingToUndo
    case unreadable(String)
    case notAList(key: String)
    case dockWriteFailed
    case dockNotRunning

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid layout name: \(name)\n"
                + "Use letters, numbers, dots, underscores, or hyphens "
                + "(max 64 characters, must start with a letter or number)."
        case .nameTaken(let existing):
            return "Layout \"\(existing)\" already uses that name."
        case .notFound(let name):
            return "No saved layout \"\(name)\"."
        case .nothingToUndo:
            return "Nothing to undo yet. A backup is taken each time a layout is loaded."
        case .unreadable(let path):
            return "Unexpected plist: \(path)"
        case .notAList(let key):
            return "Dock preference \(key) is not a list"
        case .dockWriteFailed:
            return "Couldn't write the Dock preferences."
        case .dockNotRunning:
            return "The Dock didn't come back after restarting. Your layout was saved to its settings.\n"
                + "Bring it back with: launchctl kickstart -k gui/$(id -u)/com.apple.Dock.agent"
        }
    }
}

/// Reads and writes layout files under `~/.config/docklayout`
/// (or `$DOCKLAYOUT_DIR`). The on-disk format is a binary plist per layout,
/// the same format the original Python tool wrote, so old layouts load as-is.
public struct LayoutStore {
    public static let backupsKept = 10

    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let override = environment["DOCKLAYOUT_DIR"], !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            self.init(baseDirectory: URL(fileURLWithPath: path, isDirectory: true))
        } else {
            self.init(baseDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/docklayout", isDirectory: true))
        }
    }

    public var layoutsDirectory: URL { baseDirectory.appendingPathComponent("layouts", isDirectory: true) }
    public var backupsDirectory: URL { baseDirectory.appendingPathComponent("backups", isDirectory: true) }

    // MARK: Names

    /// Letters, digits, `.`, `_`, `-`; starts with a letter or digit; 1–64 characters.
    public static func isValidName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard (1...64).contains(scalars.count), isAlphanumeric(scalars[0]) else { return false }
        return scalars.allSatisfy { isAlphanumeric($0) || $0 == "." || $0 == "_" || $0 == "-" }
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9": return true
        default: return false
        }
    }

    public static func validate(_ name: String) throws {
        guard isValidName(name) else { throw DockLayoutError.invalidName(name) }
    }

    // MARK: Layouts

    public func url(for name: String) -> URL {
        layoutsDirectory.appendingPathComponent("\(name).plist")
    }

    public func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// Saved layout names, sorted case-insensitively.
    public func names() -> [String] {
        plistFiles(in: layoutsDirectory)
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    public func read(_ name: String) throws -> Layout {
        try Self.validate(name)
        guard exists(name) else { throw DockLayoutError.notFound(name) }
        return try readPlist(url(for: name))
    }

    public func write(_ layout: Layout, as name: String) throws {
        try Self.validate(name)
        if let clash = names().first(where: { $0 != name && $0.lowercased() == name.lowercased() }) {
            throw DockLayoutError.nameTaken(existing: clash)
        }
        try writePlist(layout, to: url(for: name))
    }

    public func delete(_ name: String) throws {
        try Self.validate(name)
        guard exists(name) else { throw DockLayoutError.notFound(name) }
        try FileManager.default.removeItem(at: url(for: name))
    }

    /// The saved layout whose apps and folders match `live` exactly, if any.
    public func name(matching live: Layout) -> String? {
        names().first { name in
            guard let saved = try? readPlist(url(for: name)) else { return false }
            return layoutsEqual(saved, live)
        }
    }

    // MARK: Backups

    /// Writes `layout` as a timestamped backup and prunes all but the newest ten.
    @discardableResult
    public func backup(_ layout: Layout, at date: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)

        var target = backupsDirectory.appendingPathComponent("\(stamp).plist")
        var suffix = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = backupsDirectory.appendingPathComponent("\(stamp)-\(suffix).plist")
            suffix += 1
        }
        try writePlist(layout, to: target)

        let all = backups()
        for old in all.dropLast(Self.backupsKept) {
            try? FileManager.default.removeItem(at: old)
        }
        return target
    }

    /// Backup files, oldest first.
    public func backups() -> [URL] {
        // Compare stems so "…-1" (a second backup in the same second) sorts after its base.
        plistFiles(in: backupsDirectory).sorted {
            $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent
        }
    }

    public func readBackup(_ url: URL) throws -> Layout {
        try readPlist(url)
    }

    // MARK: Plist I/O

    private func plistFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter {
            $0.pathExtension == "plist"
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func readPlist(_ url: URL) throws -> Layout {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? Layout else {
            throw DockLayoutError.unreadable(url.path)
        }
        return plist
    }

    private func writePlist(_ layout: Layout, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(fromPropertyList: layout, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
    }
}

/// Deep comparison of the layout keys. Bookmark `Data` compares by bytes.
public func layoutsEqual(_ lhs: Layout, _ rhs: Layout) -> Bool {
    layoutKeys.allSatisfy { key in
        let left = (lhs[key] as? [Any]) ?? []
        let right = (rhs[key] as? [Any]) ?? []
        return NSArray(array: left).isEqual(to: right)
    }
}
