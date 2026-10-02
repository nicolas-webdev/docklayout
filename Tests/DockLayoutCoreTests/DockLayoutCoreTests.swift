@testable import DockLayoutCore
import Foundation
import Testing

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

/// Each test gets a fresh instance, so a fresh temporary folder and Dock.
final class DockLayoutCoreTests {
    private let directory: URL
    private let dock: FakeDock
    private let layouts: DockLayouts

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("docklayout-tests-\(UUID().uuidString)", isDirectory: true)
        dock = FakeDock(apps: ["Safari", "spacer", "Mail"], others: ["Downloads"])
        layouts = DockLayouts(store: LayoutStore(baseDirectory: directory), dock: dock)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func testNameValidation() {
        for good in ["Work", "a", "home-2", "x.y_z", String(repeating: "a", count: 64)] {
            #expect(LayoutStore.isValidName(good), "\(good)")
        }
        for bad in ["", "-work", ".hidden", "has space", "a/b", "émoji", String(repeating: "a", count: 65)] {
            #expect(!LayoutStore.isValidName(bad), "\(bad)")
        }
    }

    @Test func testDirectoryOverride() {
        let store = LayoutStore(environment: ["DOCKLAYOUT_DIR": "/tmp/somewhere"])
        #expect(store.layoutsDirectory.path == "/tmp/somewhere/layouts")
    }

    @Test func testSaveStoresOnlyLayoutKeysAndListsSorted() throws {
        try layouts.save("work")
        try layouts.save("Alpha")
        #expect(layouts.names() == ["Alpha", "work"])

        let saved = try layouts.store.read("work")
        #expect(Set(saved.keys) == Set(layoutKeys))
        #expect(layoutsEqual(saved, dock.layout))
    }

    @Test func testSaveRejectsCaseInsensitiveClash() throws {
        try layouts.save("Work")
        #expect(throws: DockLayoutError.nameTaken(existing: "Work")) { try self.layouts.save("work") }
        try layouts.save("Work") // overwriting the same name is allowed
    }

    @Test func testActiveNameTracksTheDock() throws {
        #expect(layouts.activeName() == nil)
        try layouts.save("Work")
        #expect(layouts.activeName() == "Work")
        dock.set(apps: ["Safari"])
        #expect(layouts.activeName() == nil)
        try layouts.save("Minimal")
        #expect(layouts.activeName() == "Minimal")
    }

    @Test func testBookmarkDataDifferenceBreaksMatch() throws {
        try layouts.save("Work")
        var changed = dock.layout
        var apps = changed["persistent-apps"] as! [[String: Any]]
        var tile = apps[0]["tile-data"] as! [String: Any]
        tile["book"] = Data("moved".utf8)
        apps[0]["tile-data"] = tile
        changed["persistent-apps"] = apps
        dock.layout = changed
        #expect(layouts.activeName() == nil)
    }

    @Test func testLoadBacksUpThenApplies() throws {
        try layouts.save("Work")
        dock.set(apps: ["Xcode"])
        try layouts.load("Work")

        #expect(dock.applied == 1)
        #expect(layouts.activeName() == "Work")
        #expect(layouts.store.backups().count == 1)
        let backup = try layouts.store.readBackup(layouts.store.backups()[0])
        #expect(layoutsEqual(backup, FakeDock.layout(apps: ["Xcode"])))
    }

    @Test func testLoadMissingLayout() {
        #expect(throws: DockLayoutError.notFound("Nope")) { try self.layouts.load("Nope") }
        #expect(dock.applied == 0)
        #expect(layouts.store.backups().isEmpty)
    }

    @Test func testUndoTogglesBetweenTheLastTwoDocks() throws {
        #expect(throws: DockLayoutError.nothingToUndo) { try self.layouts.undo() }
        try layouts.save("Work")
        dock.set(apps: ["Xcode"])
        try layouts.load("Work")

        try layouts.undo()
        #expect(layoutsEqual(dock.layout, FakeDock.layout(apps: ["Xcode"])))
        try layouts.undo()
        #expect(layouts.activeName() == "Work")
    }

    @Test func testBackupsWithinOneSecondSortInOrder() throws {
        let now = Date()
        let first = try layouts.store.backup(FakeDock.layout(apps: ["One"]), at: now)
        let second = try layouts.store.backup(FakeDock.layout(apps: ["Two"]), at: now)
        #expect(layouts.store.backups() == [first, second])
    }

    @Test func testBackupsArePrunedToTen() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<13 {
            try layouts.store.backup(FakeDock.layout(apps: ["\(index)"]), at: start.addingTimeInterval(Double(index)))
        }
        let backups = layouts.store.backups()
        #expect(backups.count == LayoutStore.backupsKept)
        let newest = try layouts.store.readBackup(backups.last!)
        #expect(layoutsEqual(newest, FakeDock.layout(apps: ["12"])))
    }

    @Test func testDelete() throws {
        try layouts.save("Work")
        try layouts.delete("Work")
        #expect(layouts.names() == [])
        #expect(throws: DockLayoutError.notFound("Work")) { try self.layouts.delete("Work") }
    }

    /// Layouts written by the 0.2 Python tool (binary plist, two keys) still load.
    @Test func testReadsLegacyBinaryPlist() throws {
        let legacy = FakeDock.layout(apps: ["Finder", "spacer"])
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: layouts.store.layoutsDirectory, withIntermediateDirectories: true)
        try data.write(to: layouts.store.url(for: "Old"))
        #expect(try layoutsEqual(layouts.store.read("Old"), legacy))
    }
}
