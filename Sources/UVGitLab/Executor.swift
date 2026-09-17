import Foundation
import UVCore
import Darwin

public final class GitLabExecutor {
    let services: ExecutorServices
    let config: ExecutorConfiguration
    let name: String
    let store: VMStore
    let directory: URL
    let stateURL: URL
    let lock: FileLock
    let identity: String

    public init(configuration: ExecutorConfiguration, jobResponse: Data, services: ExecutorServices = ExecutorServices()) throws {
        try configuration.validate()
        self.services = services
        config = configuration
        name = try config.jobName(response: jobResponse)
        store = VMStore(root: URL(fileURLWithPath: config.storePath))
        directory = store.root.appendingPathComponent(".gitlab/jobs/" + name)
        stateURL = directory.appendingPathComponent("state.json")
        identity = try config.identity()
        lock = try FileLock(url: store.root.appendingPathComponent(".gitlab/locks/" + name))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func readState() throws -> ExecutorJobState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        try requireRegularFile(stateURL)
        let state = try JSONDecoder().decode(ExecutorJobState.self, from: Data(contentsOf: stateURL))
        guard state.name == name, state.configurationIdentity == identity else { throw UVError("Job ownership/configuration mismatch; preserve the state and restore the original runner configuration for cleanup.") }
        return state
    }
    private func writeState(_ phase: String) throws {
        try JSONEncoder().encode(ExecutorJobState(name: name, configurationIdentity: identity, phase: phase)).write(to: stateURL, options: .atomic)
    }
    private var runtimeEnvironment: [String: String] {
        var environment: [String: String] = ["UVM_HOME": config.storePath, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for key in ["HOME", "TMPDIR"] { environment[key] = ProcessInfo.processInfo.environment[key] }
        return environment
    }
    public func configurationJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["builds_dir": config.buildsDirectory, "cache_dir": config.cacheDirectory,
            "builds_dir_is_shared": false, "hostname": name, "shell": "bash",
            "driver": ["name": "gitlab-uvm-executor", "version": "0.1.0-dev"]], options: [.sortedKeys])
    }
    private func ready() async throws -> String {
        try await services.readiness(store, name, config.ssh, config.readinessURLs, config.readinessTimeout)
    }
    public func prepare() async throws {
        if let state = try readState() {
            if state.phase == "ready", (try? services.status(store, name)) == "running" {
                _ = try await ready(); return
            }
            // A repeated prepare recovers only a clone recorded in this job's ownership journal.
            try await cleanup()
        } else if FileManager.default.fileExists(atPath: try store.directory(name).path) {
            throw UVError("Unowned job VM collision; refusing to modify it.")
        }
        try writeState("preparing")
        UVLog.emit("Creating isolated GitLab job VM.")
        if config.image.contains("/") {
            try await RegistryImages.clone(OCIReference(config.image), store: store, name: name) { _ in }
        } else { try store.clone(config.image, to: name) }
        try writeState("starting")
        try services.launch(config.uvmPath, ["run", name, "--headless"], runtimeEnvironment, directory.appendingPathComponent("runtime.log"))
        let address = try await ready()
        let setup = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; " +
            "command -v bash git git-lfs gitlab-runner curl >/dev/null && mkdir -p " +
            GuestCommand.quote(config.buildsDirectory) + " " + GuestCommand.quote(config.cacheDirectory) +
            " && test -w " + GuestCommand.quote(config.buildsDirectory) + " && test -w " + GuestCommand.quote(config.cacheDirectory)
        guard try await services.execute("/usr/bin/ssh", config.ssh.arguments(address: address, command: setup), nil, nil, true, 20) == 0 else {
            throw UVError("Guest prerequisites failed: install Bash, Git, Git LFS, curl and GitLab Runner; make build/cache directories writable by the SSH user.")
        }
        try writeState("ready")
        UVLog.emit("GitLab job VM is ready; checkout may proceed.")
    }
    public func run(script: String, stage: String, environment: [String: String]) async throws {
        guard let state = try readState(), state.phase == "ready" else { throw UVError("Job VM has not passed preparation.") }
        let scriptURL = URL(fileURLWithPath: script)
        try requireRegularFile(scriptURL)
        guard (try services.status(store, name)) == "running" else { throw UVError("Job VM is no longer running.") }
        let address: String
        if ExecutorContract.needsNetwork(stage) { address = try await ready() }
        else {
            guard let found = try await IPDiscovery.lookup(store: store, name: name) else { throw UVError("Job VM has no DHCP address.") }
            address = found
        }
        // A separate result file distinguishes a job exit 255 from SSH's transport exit 255.
        let remoteResult = "/tmp/uvm-result-" + UUID().uuidString
        let quoted = GuestCommand.quote(remoteResult)
        let command = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; umask 077; /bin/bash -s; result=$?; printf '%s\\n' \"$result\" > " + quoted
        let status = try await services.execute("/usr/bin/ssh", config.ssh.arguments(address: address, command: command), scriptURL, nil, false, config.stageTimeout)
        guard status == 0 else { throw UVError("Guest script transport failed; stage was not replayed because it may have executed.") }
        let resultURL = directory.appendingPathComponent("result-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: resultURL) }
        let readStatus = try await services.execute("/usr/bin/ssh", config.ssh.arguments(address: address, command: "cat " + quoted + "; rm -f " + quoted), nil, resultURL, true, 15)
        guard readStatus == 0, (try resultURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 999) <= 16,
              let code = Int32(try String(contentsOf: resultURL).trimmingCharacters(in: .whitespacesAndNewlines)), (0...255).contains(code) else {
            throw UVError("Cannot confirm the guest stage result; stage was not replayed.")
        }
        if code != 0 {
            if let path = environment["BUILD_EXIT_CODE_FILE"] { try Data(String(code).utf8).write(to: URL(fileURLWithPath: path)) }
            throw ExecutorFailure.build(code)
        }
    }
    public func cleanup() async throws {
        guard try readState() != nil else { return }
        if FileManager.default.fileExists(atPath: try store.directory(name).path) {
            var state = try services.status(store, name)
            if state != "stopped" {
                // CI clones are disposable. Force-stop is bounded and avoids guest shutdown dialogs.
                try await services.stop(store, name)
                let deadline = ProcessInfo.processInfo.systemUptime + 20
                repeat {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    state = try services.status(store, name)
                } while state != "stopped" && ProcessInfo.processInfo.systemUptime < deadline
                guard state == "stopped" else { throw UVError("Job VM did not stop; preserving ownership journal for cleanup retry.") }
            }
            try store.delete(name)
        }
        try FileManager.default.removeItem(at: stateURL)
        UVLog.emit("GitLab job VM cleaned up.")
    }
}
