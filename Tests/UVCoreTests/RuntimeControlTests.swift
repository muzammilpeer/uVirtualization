import XCTest
@testable import UVCore

final class RuntimeControlTests: XCTestCase {
    func testStaleStatusDoesNotReportRunning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "vm"))
        let dir = try RuntimeControl.directory(store: store, name: "vm")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(RuntimeStatus(name: "vm", state: "running", processID: 123, session: "old"))
            .write(to: dir.appendingPathComponent("status.json"))
        XCTAssertEqual(try RuntimeControl.status(store: store, name: "vm").state, "stopped")
        let lock = try store.lock("vm")
        defer { lock.unlock() }
        XCTAssertEqual(try RuntimeControl.status(store: store, name: "vm").state, "running")
    }
    func testStoppedGuestRejectsControl() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VMStore(root: root)
        try store.create(VMConfiguration(name: "vm"))
        do { try await RuntimeControl.send(store: store, name: "vm", command: "stop"); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not accepting")) }
    }
}
