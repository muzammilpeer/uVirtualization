import Foundation
import Darwin

/// Runs without a shell on the host. Probe output is suppressed to avoid leaking endpoints or credentials.
public enum ChildProcess {
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                           input: URL? = nil, output: URL? = nil, quiet: Bool = false, timeout: TimeInterval = 3600) async throws -> Int32 {
        try Task.checkCancellation()
        guard timeout > 0, timeout.isFinite else { throw UVError("Process deadline expired.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let handle = try input.map { try FileHandle(forReadingFrom: $0) }
        defer { try? handle?.close() }
        process.standardInput = handle ?? FileHandle.nullDevice
        let outputHandle: FileHandle?
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw UVError("Cannot create command output file.") }
            outputHandle = try FileHandle(forWritingTo: output)
        } else { outputHandle = nil }
        defer { try? outputHandle?.close() }
        process.standardOutput = outputHandle ?? (quiet ? FileHandle.nullDevice : FileHandle.standardOutput)
        process.standardError = quiet ? FileHandle.nullDevice : FileHandle.standardError
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw UVError("Child process exceeded its deadline.") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public struct GuestSSH: Codable, Equatable {
    public var user: String
    public var identityFile: String
    public var knownHostsFile: String
    public var hostKeyAlias: String
    public init(user: String, identityFile: String, knownHostsFile: String, hostKeyAlias: String) throws {
        self.user = user; self.identityFile = identityFile; self.knownHostsFile = knownHostsFile; self.hostKeyAlias = hostKeyAlias
        try validate()
    }
    public func validate() throws {
        guard user.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil,
              hostKeyAlias.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", options: .regularExpression) != nil,
              identityFile.hasPrefix("/"), knownHostsFile.hasPrefix("/"),
              !identityFile.contains("\n"), !knownHostsFile.contains("\n") else { throw UVError("Invalid SSH user, host alias or absolute key paths.") }
    }
    public func arguments(address: String, command: String) throws -> [String] {
        try validate()
        let octets = address.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { throw UVError("Invalid guest IPv4 address.") }
        return ["-F", "/dev/null", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=5", "-o", "ConnectionAttempts=1",
                "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
                "-o", "UserKnownHostsFile=" + knownHostsFile, "-o", "HostKeyAlias=" + hostKeyAlias,
                "-i", identityFile, "--", user + "@" + address, command]
    }
}

public enum ReadinessGate {
    /// Injectable clock/probe/sleep lets tests verify the deadline and consecutive successes without real delays.
    public static func wait(timeout: Double, consecutive: Int = 2,
                            now: () -> Double = { ProcessInfo.processInfo.systemUptime },
                            sleep: (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                            probe: (Double) async throws -> Bool) async throws {
        guard timeout.isFinite, (1...3600).contains(timeout), (1...5).contains(consecutive) else { throw UVError("Invalid readiness deadline or success count.") }
        let deadline = now() + timeout
        var successes = 0
        while now() < deadline {
            try Task.checkCancellation()
            let passed = try await probe(deadline - now())
            guard now() < deadline else { break }
            successes = passed ? successes + 1 : 0
            if successes >= consecutive { return }
            try await sleep(min(2, max(0, deadline - now())))
        }
        throw UVError("Guest readiness deadline exceeded: verify DHCP, SSH identity/access, guest DNS, TLS trust and the configured HTTPS endpoints. Checkout has not started.")
    }
}

public enum GuestReadiness {
    public static func validateEndpoints(_ endpoints: [String]) throws {
        guard (1...8).contains(endpoints.count) else { throw UVError("Configure 1–8 HTTPS readiness endpoints.") }
        for endpoint in endpoints {
            guard let url = URLComponents(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  !endpoint.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                throw UVError("Readiness endpoints must use HTTPS without credentials, query strings or fragments.")
            }
        }
    }
    public static func probeCommand(_ endpoints: [String]) throws -> String {
        try validateEndpoints(endpoints)
        return "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; command -v curl >/dev/null 2>&1 && " + endpoints.map {
            "curl --silent --fail --output /dev/null --proto '=https' --connect-timeout 4 --max-time 8 " + GuestCommand.quote($0)
        }.joined(separator: " && ")
    }
    public static func wait(store: VMStore, name: String, ssh: GuestSSH, endpoints: [String], timeout: Double = 180,
                            progress: (String) -> Void = { _ in }) async throws -> String {
        let command = try probeCommand(endpoints)
        try ssh.validate()
        try requireRegularFile(URL(fileURLWithPath: ssh.identityFile))
        try requireRegularFile(URL(fileURLWithPath: ssh.knownHostsFile))
        var address: String?
        var previousAddress: String?
        progress("Waiting for running guest, DHCP, authenticated SSH and guest HTTPS connectivity.")
        try await ReadinessGate.wait(timeout: timeout) { remaining in
            guard try RuntimeControl.status(store: store, name: name).state == "running" else { return false }
            guard let current = try await IPDiscovery.lookup(store: store, name: name) else { return false }
            if previousAddress != current { previousAddress = current; address = nil; return false }
            do {
                let status = try await ChildProcess.run("/usr/bin/ssh", ssh.arguments(address: current, command: command), quiet: true, timeout: min(remaining, Double(endpoints.count * 8 + 6)))
                if status == 0 { address = current; return true }
                let reason: String
                switch status {
                case 255: reason = "SSH connection, host verification or authentication"
                case 6: reason = "Guest DNS resolution"
                case 7: reason = "Guest endpoint connection"
                case 22: reason = "Guest endpoint HTTP response"
                case 28: reason = "Guest endpoint timeout"
                case 60: reason = "Guest TLS certificate validation"
                default: reason = "Guest HTTPS probe (exit \(status))"
                }
                progress(reason + " failed; retrying within the readiness deadline.")
                return false
            } catch is CancellationError { throw CancellationError() }
            catch { return false }
        }
        guard let address else { throw UVError("Guest address changed during readiness check.") }
        progress("Guest network readiness verified.")
        return address
    }
}
