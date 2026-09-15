import XCTest
@testable import UVCore

final class StorageTransactionTests: XCTestCase {
    func testExclusiveLockAndRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        let first = try store.lock("vm")
        XCTAssertThrowsError(try store.lock("vm"))
        first.unlock()
        let second = try store.lock("vm")
        second.unlock()
    }
    func testStageIsInvisibleAndPublishIsExclusive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        let stage = try store.stage("vm")
        try store.save(VMConfiguration(name: "vm"), at: stage)
        XCTAssertEqual(try store.list(), [])
        try store.publish(stage, name: "vm")
        XCTAssertEqual(try store.list().count, 1)
        XCTAssertThrowsError(try store.stage("vm"))
    }
    func testSparseDiskDoesNotOverwrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try SparseDisk.create(at: url, bytes: 1_073_741_824)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        XCTAssertEqual(size?.uint64Value, 1_073_741_824)
        XCTAssertThrowsError(try SparseDisk.create(at: url, bytes: 1))
    }
}
