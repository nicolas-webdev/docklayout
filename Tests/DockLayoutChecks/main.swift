// Checks for DockLayoutCore, run with `swift run DockLayoutChecks`.
//
// A plain executable rather than XCTest or Swift Testing: XCTest only ships
// with full Xcode, and the Command Line Tools' build system can't load the
// Swift Testing macros. This runs anywhere Swift does.
import DockLayoutCore
import Foundation

/// Stands in for the real Dock: holds a layout in memory and counts applies.
final class FakeDock: DockBackend {
    var layout: Layout
    var applied = 0

    init(apps: [String], others: [String] = []) {
        layout = FakeDock.layout(apps: apps, others: others)
    }

    static func layout(apps: [String], others: [String] = []) -> Layout {
        func tiles(_ labels: [String]) -> [Any] {
            labels.map { label -> Any in
                label == "spacer"
                    ? ["tile-type": "spacer-tile", "tile-data": [String: Any]()]
                    : ["tile-type": "file-tile", "tile-data": ["file-label": label, "book": Data(label.utf8)]]
            }
        }
        return ["persistent-apps": tiles(apps), "persistent-others": tiles(others)]
    }

    func readLayout() throws -> Layout {
        // The real Dock domain has many more keys; only the layout keys may be kept.
        layout.merging(["tilesize": 48, "autohide": true]) { current, _ in current }
    }

    func apply(_ layout: Layout) throws {
        self.layout = layout
        applied += 1
    }

    func set(apps: [String], others: [String] = []) {
        layout = FakeDock.layout(apps: apps, others: others)
    }
}

/// A fresh temporary folder and Dock for each check.
struct Fixture {
    let dock = FakeDock(apps: ["Safari", "spacer", "Mail"], others: ["Downloads"])
    let layouts: DockLayouts

    init(directory: URL) {
        layouts = DockLayouts(store: LayoutStore(baseDirectory: directory), dock: dock)
    }
}

var issues: [String] = []

func expect(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        issues.append("line \(line)\(message.isEmpty ? "" : ": \(message)")")
    }
}

func expect<E: Error & Equatable>(throws expected: E, line: UInt = #line, _ body: () throws -> Void) {
    do {
        try body()
        issues.append("line \(line): expected \(expected) to be thrown")
    } catch let error as E where error == expected {
    } catch {
        issues.append("line \(line): expected \(expected), got \(error)")
    }
}

var checks: [(String, (Fixture) throws -> Void)] = []
func check(_ name: String, _ body: @escaping (Fixture) throws -> Void) {
    checks.append((name, body))
}

// MARK: Checks

check("name validation") { _ in
    for good in ["Work", "a", "home-2", "x.y_z", String(repeating: "a", count: 64)] {
        expect(LayoutStore.isValidName(good), good)
    }
    for bad in ["", "-work", ".hidden", "has space", "a/b", "émoji", String(repeating: "a", count: 65)] {
        expect(!LayoutStore.isValidName(bad), bad)
    }
}

check("DOCKLAYOUT_DIR override") { _ in
    let store = LayoutStore(environment: ["DOCKLAYOUT_DIR": "/tmp/somewhere"])
    expect(store.layoutsDirectory.path == "/tmp/somewhere/layouts")
}

check("save stores only layout keys and lists sorted") { f in
    try f.layouts.save("work")
    try f.layouts.save("Alpha")
    expect(f.layouts.names() == ["Alpha", "work"])
    let saved = try f.layouts.store.read("work")
    expect(Set(saved.keys) == Set(layoutKeys))
    expect(layoutsEqual(saved, f.dock.layout))
}

check("save rejects a case-insensitive clash") { f in
    try f.layouts.save("Work")
    expect(throws: DockLayoutError.nameTaken(existing: "Work")) { try f.layouts.save("work") }
    try f.layouts.save("Work") // overwriting the same name is allowed
}

check("active name tracks the Dock") { f in
    expect(f.layouts.activeName() == nil)
    try f.layouts.save("Work")
    expect(f.layouts.activeName() == "Work")
    f.dock.set(apps: ["Safari"])
    expect(f.layouts.activeName() == nil)
    try f.layouts.save("Minimal")
    expect(f.layouts.activeName() == "Minimal")
}

check("different bookmark data breaks the match") { f in
    try f.layouts.save("Work")
    var changed = f.dock.layout
    var apps = changed["persistent-apps"] as! [[String: Any]]
    var tile = apps[0]["tile-data"] as! [String: Any]
    tile["book"] = Data("moved".utf8)
    apps[0]["tile-data"] = tile
    changed["persistent-apps"] = apps
    f.dock.layout = changed
    expect(f.layouts.activeName() == nil)
}

check("load backs up, then applies") { f in
    try f.layouts.save("Work")
    f.dock.set(apps: ["Xcode"])
    try f.layouts.load("Work")
    expect(f.dock.applied == 1)
    expect(f.layouts.activeName() == "Work")
    expect(f.layouts.store.backups().count == 1)
    let backup = try f.layouts.store.readBackup(f.layouts.store.backups()[0])
    expect(layoutsEqual(backup, FakeDock.layout(apps: ["Xcode"])))
}

check("loading a missing layout changes nothing") { f in
    expect(throws: DockLayoutError.notFound("Nope")) { try f.layouts.load("Nope") }
    expect(f.dock.applied == 0)
    expect(f.layouts.store.backups().isEmpty)
}

check("undo toggles between the last two Docks") { f in
    expect(throws: DockLayoutError.nothingToUndo) { try f.layouts.undo() }
    try f.layouts.save("Work")
    f.dock.set(apps: ["Xcode"])
    try f.layouts.load("Work")
    try f.layouts.undo()
    expect(layoutsEqual(f.dock.layout, FakeDock.layout(apps: ["Xcode"])))
    try f.layouts.undo()
    expect(f.layouts.activeName() == "Work")
}

check("backups within one second sort in order") { f in
    let now = Date()
    let first = try f.layouts.store.backup(FakeDock.layout(apps: ["One"]), at: now)
    let second = try f.layouts.store.backup(FakeDock.layout(apps: ["Two"]), at: now)
    // Compare names: on macOS the temp folder is reached through the /var → /private/var symlink.
    expect(f.layouts.store.backups().map(\.lastPathComponent) == [first.lastPathComponent, second.lastPathComponent])
}

check("backups are pruned to ten") { f in
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for index in 0..<13 {
        try f.layouts.store.backup(FakeDock.layout(apps: ["\(index)"]), at: start.addingTimeInterval(Double(index)))
    }
    let backups = f.layouts.store.backups()
    expect(backups.count == LayoutStore.backupsKept)
    expect(layoutsEqual(try f.layouts.store.readBackup(backups.last!), FakeDock.layout(apps: ["12"])))
}

check("delete") { f in
    try f.layouts.save("Work")
    try f.layouts.delete("Work")
    expect(f.layouts.names() == [])
    expect(throws: DockLayoutError.notFound("Work")) { try f.layouts.delete("Work") }
}

check("reads layouts written by the 0.2 Python tool") { f in
    let legacy = FakeDock.layout(apps: ["Finder", "spacer"])
    let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
    try FileManager.default.createDirectory(at: f.layouts.store.layoutsDirectory, withIntermediateDirectories: true)
    try data.write(to: f.layouts.store.url(for: "Old"))
    expect(layoutsEqual(try f.layouts.store.read("Old"), legacy))
}

// MARK: Run

var failed = 0
for (name, body) in checks {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("docklayout-checks-\(UUID().uuidString)", isDirectory: true)
    issues = []
    do {
        try body(Fixture(directory: directory))
    } catch {
        issues.append("threw \(error)")
    }
    try? FileManager.default.removeItem(at: directory)
    if issues.isEmpty {
        print("✔ \(name)")
    } else {
        failed += 1
        print("✘ \(name)")
        issues.forEach { print("    \($0)") }
    }
}
print(failed == 0 ? "\(checks.count) checks passed" : "\(failed) of \(checks.count) checks failed")
exit(failed == 0 ? 0 : 1)
