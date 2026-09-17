import XCTest
@testable import UVCore

final class GuestReadinessTests: XCTestCase {
    func testGateRequiresConsecutiveSuccessesAndResetsAfterFailure() async throws {
        var clock = 0.0
        var outcomes = [false, true, false, true, true]
        var attempts = 0
        try await ReadinessGate.wait(timeout: 20, now: { clock }, sleep: { clock += $0 }) { remaining in
            XCTAssertGreaterThan(remaining, 0)
            attempts += 1
            return outcomes.removeFirst()
        }
        XCTAssertEqual(attempts, 5)
        XCTAssertEqual(clock, 8)
    }
    func testUnhealthyNetworkStopsAtDeadline() async {
        var clock = 0.0
        var attempts = 0
        do {
            try await ReadinessGate.wait(timeout: 5, now: { clock }, sleep: { clock += $0 }) { _ in attempts += 1; return false }
            XCTFail("Expected deadline")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Checkout has not started")) }
        XCTAssertEqual(clock, 5)
        XCTAssertEqual(attempts, 3)
    }
    func testOverDeadlineSuccessIsRejected() async {
        var clock = 0.0
        do {
            try await ReadinessGate.wait(timeout: 5, consecutive: 1, now: { clock }, sleep: { clock += $0 }) { _ in clock = 6; return true }
            XCTFail("Late success must not pass")
        } catch {}
    }
    func testEndpointAndSSHValidation() throws {
        for endpoint in ["http://gitlab.example", "https://user:secret@gitlab.example", "https://gitlab.example/?token=secret", "https://gitlab.example/#secret", "https://"] {
            XCTAssertThrowsError(try GuestReadiness.validateEndpoints([endpoint]))
        }
        XCTAssertThrowsError(try GuestReadiness.validateEndpoints([]))
        let command = try GuestReadiness.probeCommand(["https://gitlab.muzammilpeer.uk/"])
        XCTAssertTrue(command.contains("--proto '=https'"))
        XCTAssertFalse(command.contains("--insecure"))
        let ssh = try GuestSSH(user: "builder", identityFile: "/tmp/key", knownHostsFile: "/tmp/hosts", hostKeyAlias: "ci-image")
        let args = try ssh.arguments(address: "192.168.64.2", command: "true")
        XCTAssertTrue(args.contains("StrictHostKeyChecking=yes"))
        XCTAssertThrowsError(try ssh.arguments(address: "-oProxyCommand=bad", command: "true"))
    }
    func testMissingDHCPFileIsNotFatal() throws {
        XCTAssertEqual(try IPDiscovery.readLeases(at: "/tmp/uvm-no-leases-" + UUID().uuidString), "")
    }
    func testChildProcessDeadlineTerminatesProbe() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        do { _ = try await ChildProcess.run("/bin/sleep", ["30"], quiet: true, timeout: 0.2); XCTFail("Expected timeout") }
        catch { XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3) }
    }
}
