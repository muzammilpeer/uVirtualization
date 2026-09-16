import Foundation

public struct GuestExit: Error { public let status: Int32 }
public enum GuestCommand {
    public static func quote(_ argument: String) -> String { "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func execute(address: String, user: String, arguments: [String]) async throws {
        guard !arguments.isEmpty, user.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else { throw UVError("A valid SSH user and guest command are required.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "--", user + "@" + address, arguments.map(quote).joined(separator: " ")]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
            }
        } onCancel: { if process.isRunning { process.terminate() } }
        if status != 0 { throw GuestExit(status: status) }
    }
}
