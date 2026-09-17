import Foundation
import UVCore
import Darwin

/// Dependencies are explicit so the Runner contract can be tested without launching a guest.
public struct ExecutorServices {
    public var readiness: (VMStore, String, GuestSSH, [String], Double) async throws -> String = { store, name, ssh, urls, timeout in
        try await GuestReadiness.wait(store: store, name: name, ssh: ssh, endpoints: urls, timeout: timeout) { UVLog.emit($0) }
    }
    public var status: (VMStore, String) throws -> String = { try RuntimeControl.status(store: $0, name: $1).state }
    public var stop: (VMStore, String) async throws -> Void = { try await RuntimeControl.send(store: $0, name: $1, command: "force-stop", timeout: 20) }
    public var execute: (String, [String], URL?, URL?, Bool, Double) async throws -> Int32 = { executable, arguments, input, output, quiet, timeout in
        try await ChildProcess.run(executable, arguments, input: input, output: output, quiet: quiet, timeout: timeout)
    }
    public var launch: (String, [String], [String: String], URL) throws -> Void = { executable, arguments, environment, log in
        var attributes: posix_spawnattr_t?
        var actions: posix_spawn_file_actions_t?
        guard posix_spawnattr_init(&attributes) == 0 else { throw UVError("Cannot initialize runtime attributes.") }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw UVError("Cannot initialize runtime file actions.") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600) == 0,
              posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO) == 0 else {
            throw UVError("Cannot configure detached runtime.")
        }
        let argv = ([executable] + arguments).map { strdup($0) }
        let env = environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) }
        defer { (argv + env).forEach { free($0) } }
        var argvPointers = argv + [nil]
        var envPointers = env + [nil]
        var pid: pid_t = 0
        let result = argvPointers.withUnsafeMutableBufferPointer { argvBuffer in
            envPointers.withUnsafeMutableBufferPointer { envBuffer in
                posix_spawn(&pid, executable, &actions, &attributes, argvBuffer.baseAddress!, envBuffer.baseAddress!)
            }
        }
        guard result == 0 else { throw UVError("Cannot launch detached VM runtime: " + String(cString: strerror(result))) }

    }
    public init() {}
}
