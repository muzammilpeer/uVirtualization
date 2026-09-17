import XCTest
@testable import UVCore

final class RenameRecoveryTests: XCTestCase {
    func testRenameCrashAfterDirectoryMoveRecovers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "old"))
        let journals = root.appendingPathComponent(".transactions")
        try FileManager.default.createDirectory(at: journals, withIntermediateDirectories: true)
        let journal = journals.appendingPathComponent("test.json")
        try JSONEncoder().encode(RenameTransaction(source: "old", destination: "new")).write(to: journal)
        try FileManager.default.moveItem(at: store.directory("old"), to: store.directory("new"))
        XCTAssertEqual(try store.list().map(\.name), ["new"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }
    func testAmbiguousJournalPreservesData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "old"))
        try store.create(VMConfiguration(name: "new"))
        let journals = root.appendingPathComponent(".transactions")
        try FileManager.default.createDirectory(at: journals, withIntermediateDirectories: true)
        try JSONEncoder().encode(RenameTransaction(source: "old", destination: "new")).write(to: journals.appendingPathComponent("test.json"))
        XCTAssertThrowsError(try store.recoverRenames())
        XCTAssertEqual(try store.load("old").name, "old")
        XCTAssertEqual(try store.load("new").name, "new")
    }
}
