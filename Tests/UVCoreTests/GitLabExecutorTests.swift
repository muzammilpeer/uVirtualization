import XCTest
@testable import UVCore
@testable import UVGitLab

final class GitLabExecutorTests: XCTestCase {
    func fixture() throws -> (ExecutorConfiguration, VMStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let config = ExecutorConfiguration(runnerID: "local", uvmPath: "/usr/local/bin/uvm", storePath: root.path,
            image: "base", ssh: try GuestSSH(user: "builder", identityFile: "/tmp/key", knownHostsFile: "/tmp/hosts", hostKeyAlias: "base"),
            readinessURLs: ["https://gitlab.muzammilpeer.uk/"], readinessTimeout: 10,
            buildsDirectory: "/tmp/builds", cacheDirectory: "/tmp/cache", stageTimeout: 60)
        let store = VMStore(root: root)
        var model = try VMConfiguration(name: "base", guest: "linux")
        model.state = "ready"
        try store.create(model)
        try Data([1]).write(to: store.directory("base").appendingPathComponent("disk.img"))
        try Data([2]).write(to: store.directory("base").appendingPathComponent("efi.bin"))
        return (config, store)
    }
    func testTrustedJobIdentityIgnoresJobVariablesAndSeparatesJobs() throws {
        let (config, _) = try fixture()
        let first = try config.jobName(response: Data("{\"id\":42,\"variables\":[{\"key\":\"CI_JOB_ID\",\"value\":\"other\"}]}".utf8))
        XCTAssertEqual(first, try config.jobName(response: Data("{\"id\":42}".utf8)))
        XCTAssertNotEqual(first, try config.jobName(response: Data("{\"id\":43}".utf8)))
        XCTAssertThrowsError(try config.jobName(response: Data("{\"id\":-1}".utf8)))
    }
    func testPrepareCheckoutGateFailureMappingAndIdempotentCleanup() async throws {
        let (config, store) = try fixture()
        var services = ExecutorServices()
        var state = "stopped"
        var probes = 0
        var scriptRuns = 0
        var failNetwork = false
        var guestExit = 0
        services.status = { _, _ in state }
        services.launch = { _, _, env, _ in
            XCTAssertNil(env["CUSTOM_ENV_CI_JOB_TOKEN"])
            state = "running"
        }
        services.stop = { _, _ in state = "stopped" }
        services.readiness = { _, _, _, _, _ in
            probes += 1
            if failNetwork { throw UVError("Injected DNS failure") }
            return "192.168.64.2"
        }
        services.execute = { _, _, input, output, _, _ in
            if input != nil { scriptRuns += 1 }
            if let output { try Data("\(guestExit)\n".utf8).write(to: output) }
            return 0
        }
        let driver = try GitLabExecutor(configuration: config, jobResponse: Data("{\"id\":42}".utf8), services: services)
        try await driver.prepare()
        XCTAssertEqual(try store.list().count, 2)
        try await driver.prepare() // does not re-clone the running VM
        let script = store.root.appendingPathComponent(".script")
        try Data("exit 7\n".utf8).write(to: script)
        failNetwork = true
        do { try await driver.run(script: script.path, stage: "get_sources", environment: [:]); XCTFail("Network gate must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("DNS")) }
        XCTAssertEqual(scriptRuns, 0)
        failNetwork = false
        guestExit = 255
        let exitFile = store.root.appendingPathComponent(".exit")
        do { try await driver.run(script: script.path, stage: "get_sources", environment: ["BUILD_EXIT_CODE_FILE": exitFile.path]); XCTFail("Expected job failure") }
        catch ExecutorFailure.build(let code) { XCTAssertEqual(code, 255) }
        XCTAssertEqual(try String(contentsOf: exitFile), "255")
        XCTAssertEqual(scriptRuns, 1)
        XCTAssertEqual(probes, 4)
        try await driver.cleanup()
        try await driver.cleanup()
        XCTAssertEqual(try store.list().map(\.name), ["base"])
    }
    func testFailedPrepareCanBeRecoveredWithoutTouchingBase() async throws {
        let (config, store) = try fixture()
        var services = ExecutorServices()
        services.launch = { _, _, _, _ in }
        services.status = { _, _ in "stopped" }
        var fail = true
        services.readiness = { _, _, _, _, _ in if fail { throw UVError("not ready") }; return "192.168.64.2" }
        services.execute = { _, _, _, _, _, _ in 0 }
        let driver = try GitLabExecutor(configuration: config, jobResponse: Data("{\"id\":99}".utf8), services: services)
        do { try await driver.prepare(); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(try store.list().count, 2)
        fail = false
        try await driver.prepare()
        try await driver.cleanup()
        XCTAssertEqual(try store.list().map(\.name), ["base"])
    }
    func testTwoJobsHaveSeparateClonesAndCleanupOwnership() async throws {
        let (config, store) = try fixture()
        var services = ExecutorServices()
        services.launch = { _, _, _, _ in }
        services.status = { _, _ in "stopped" }
        services.readiness = { _, _, _, _, _ in "192.168.64.2" }
        services.execute = { _, _, _, _, _, _ in 0 }
        let first = try GitLabExecutor(configuration: config, jobResponse: Data("{\"id\":1}".utf8), services: services)
        let second = try GitLabExecutor(configuration: config, jobResponse: Data("{\"id\":2}".utf8), services: services)
        try await first.prepare()
        try await second.prepare()
        let clones = try store.list().filter { $0.name != "base" }
        XCTAssertEqual(clones.count, 2)
        XCTAssertNotEqual(clones[0].macAddress, clones[1].macAddress)
        try await first.cleanup()
        XCTAssertEqual(try store.list().count, 2)
        try await second.cleanup()
        XCTAssertEqual(try store.list().map(\.name), ["base"])
    }
    func testTransportFailureIsNotReplayedOrMarkedBuildFailure() async throws {
        let (config, store) = try fixture()
        var services = ExecutorServices()
        services.launch = { _, _, _, _ in }
        services.status = { _, _ in "running" }
        services.readiness = { _, _, _, _, _ in "192.168.64.2" }
        var executions = 0
        services.execute = { _, _, input, _, _, _ in
            if input != nil { executions += 1; return 255 }
            return 0
        }
        let driver = try GitLabExecutor(configuration: config, jobResponse: Data("{\"id\":3}".utf8), services: services)
        try await driver.prepare()
        let script = store.root.appendingPathComponent(".script")
        try Data("true".utf8).write(to: script)
        do { try await driver.run(script: script.path, stage: "get_sources", environment: [:]); XCTFail("Expected transport failure") }
        catch let error as UVError { XCTAssertTrue(error.message.contains("not replayed")) }
        XCTAssertEqual(executions, 1)
    }
    func testConfigurationRejectsWritableSharedFile() throws {
        let (config, store) = try fixture()
        let url = store.root.appendingPathComponent(".executor.json")
        try JSONEncoder().encode(config).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
        XCTAssertThrowsError(try ExecutorConfiguration.load(url.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(try ExecutorConfiguration.load(url.path).runnerID, config.runnerID)
    }
    func testFailureCodesAndNetworkStages() {
        XCTAssertEqual(ExecutorContract.failureCode(build: true, environment: ["BUILD_FAILURE_EXIT_CODE": "42"]), 42)
        XCTAssertEqual(ExecutorContract.failureCode(build: false, environment: ["SYSTEM_FAILURE_EXIT_CODE": "43"]), 43)
        XCTAssertTrue(ExecutorContract.needsNetwork("get_sources"))
        XCTAssertTrue(ExecutorContract.needsNetwork("upload_artifacts_on_success"))
        XCTAssertFalse(ExecutorContract.needsNetwork("step_script"))
    }
}
