import XCTest
@testable import UVCore

final class GuestCommandTests: XCTestCase {
    func testShellArgumentsPreserveLiteralContent() {
        XCTAssertEqual(GuestCommand.quote("hello world"), "'hello world'")
        XCTAssertEqual(GuestCommand.quote("a'b"), "'a'\\''b'")
        XCTAssertEqual(GuestCommand.quote("$(touch /tmp/no)"), "'$(touch /tmp/no)'")
    }
}
