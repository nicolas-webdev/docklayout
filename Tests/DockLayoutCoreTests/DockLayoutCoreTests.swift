@testable import DockLayoutCore
import Foundation
import XCTest

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

final class DockLayoutCoreTests: XCTestCase {
    private var directory: URL!
    private var dock: FakeDock!
    private var layouts: DockLayouts!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("docklayout-tests-\(UUID().uuidString)", isDirectory: true)
        dock = FakeDock(apps: ["Safari", "spacer", "Mail"], others: ["Downloads"])
        layouts = DockLayouts(store: LayoutStore(baseDirectory: directory), dock: dock)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testNameValidation() {
        for good in ["Work", "a", "home-2", "x.y_z", String(repeating: "a", count: 64)] {
            XCTAssertTrue(LayoutStore.isValidName(good), good)
        }
        for bad in ["", "-work", ".hidden", "has space", "a/b", "émoji", String(repeating: "a", count: 65)] {
            XCTAssertFalse(LayoutStore.isValidName(bad), bad)
        }
    }

    func testDirectoryOverride() {
        let store = LayoutStore(environment: ["DOCKLAYOUT_DIR": "/tmp/somewhere"])
        XCTAssertEqual(store.layoutsDirectory.path, "/tmp/somewhere/layouts")
    }

    func testSaveStoresOnlyLayoutKeysAndListsSorted() throws {
        try layouts.save("work")
        try layouts.save("Alpha")
        XCTAssertEqual(layouts.names(), ["Alpha", "work"])

        let saved = try layouts.store.read("work")
        XCTAssertEqual(Set(saved.keys), Set(layoutKeys))
        XCTAssertTrue(layoutsEqual(saved, dock.layout))
    }

    func testSaveRejectsCaseInsensitiveClash() throws {
        try layouts.save("Work")
        XCTAssertThrowsError(try layouts.save("work")) {
            XCTAssertEqual($0 as? DockLayoutError, .nameTaken(existing: "Work"))
        }
        XCTAssertNoThrow(try layouts.save("Work"), "Overwriting the same name is allowed")
    }

    func testActiveNameTracksTheDock() throws {
        XCTAssertNil(layouts.activeName())
        try layouts.save("Work")
        XCTAssertEqual(layouts.activeName(), "Work")
        dock.set(apps: ["Safari"])
        XCTAssertNil(layouts.activeName())
        try layouts.save("Minimal")
        XCTAssertEqual(layouts.activeName(), "Minimal")
    }

    func testBookmarkDataDifferenceBreaksMatch() throws {
        try layouts.save("Work")
        var changed = dock.layout
        var apps = changed["persistent-apps"] as! [[String: Any]]
        var tile = apps[0]["tile-data"] as! [String: Any]
        tile["book"] = Data("moved".utf8)
        apps[0]["tile-data"] = tile
        changed["persistent-apps"] = apps
        dock.layout = changed
        XCTAssertNil(layouts.activeName())
    }

    func testLoadBacksUpThenApplies() throws {
        try layouts.save("Work")
        dock.set(apps: ["Xcode"])
        try layouts.load("Work")

        XCTAssertEqual(dock.applied, 1)
        XCTAssertEqual(layouts.activeName(), "Work")
        XCTAssertEqual(layouts.store.backups().count, 1)
        let backup = try layouts.store.readBackup(layouts.store.backups()[0])
        XCTAssertTrue(layoutsEqual(backup, FakeDock.layout(apps: ["Xcode"])))
    }

    func testLoadMissingLayout() {
        XCTAssertThrowsError(try layouts.load("Nope")) {
            XCTAssertEqual($0 as? DockLayoutError, .notFound("Nope"))
        }
        XCTAssertEqual(dock.applied, 0)
        XCTAssertTrue(layouts.store.backups().isEmpty)
    }

    func testUndoTogglesBetweenTheLastTwoDocks() throws {
        XCTAssertThrowsError(try layouts.undo()) {
            XCTAssertEqual($0 as? DockLayoutError, .nothingToUndo)
        }
        try layouts.save("Work")
        dock.set(apps: ["Xcode"])
        try layouts.load("Work")

        try layouts.undo()
        XCTAssertTrue(layoutsEqual(dock.layout, FakeDock.layout(apps: ["Xcode"])))
        try layouts.undo()
        XCTAssertEqual(layouts.activeName(), "Work")
    }

    func testBackupsWithinOneSecondSortInOrder() throws {
        let now = Date()
        let first = try layouts.store.backup(FakeDock.layout(apps: ["One"]), at: now)
        let second = try layouts.store.backup(FakeDock.layout(apps: ["Two"]), at: now)
        XCTAssertEqual(layouts.store.backups(), [first, second])
    }

    func testBackupsArePrunedToTen() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<13 {
            try layouts.store.backup(FakeDock.layout(apps: ["\(index)"]), at: start.addingTimeInterval(Double(index)))
        }
        let backups = layouts.store.backups()
        XCTAssertEqual(backups.count, LayoutStore.backupsKept)
        let newest = try layouts.store.readBackup(backups.last!)
        XCTAssertTrue(layoutsEqual(newest, FakeDock.layout(apps: ["12"])))
    }

    func testDelete() throws {
        try layouts.save("Work")
        try layouts.delete("Work")
        XCTAssertEqual(layouts.names(), [])
        XCTAssertThrowsError(try layouts.delete("Work"))
    }

    /// Layouts written by the 0.2 Python tool (binary plist, two keys) still load.
    func testReadsLegacyBinaryPlist() throws {
        let legacy = FakeDock.layout(apps: ["Finder", "spacer"])
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: layouts.store.layoutsDirectory, withIntermediateDirectories: true)
        try data.write(to: layouts.store.url(for: "Old"))
        XCTAssertTrue(layoutsEqual(try layouts.store.read("Old"), legacy))
    }
}
