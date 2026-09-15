import Foundation

public struct UVError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct VMConfiguration: Codable, Equatable {
    public let schemaVersion: Int
    public let name: String
    public let guest: String
    public let cpuCount: Int
    public let memoryMiB: Int
    public let diskGiB: Int
    public let displayWidth: Int
    public let displayHeight: Int
    public let state: String

    public init(name: String, cpuCount: Int = 4, memoryMiB: Int = 4096, diskGiB: Int = 64) throws {
        self.schemaVersion = 1
        self.name = name
        self.guest = "macOS"
        self.cpuCount = cpuCount
        self.memoryMiB = memoryMiB
        self.diskGiB = diskGiB
        self.displayWidth = 1920
        self.displayHeight = 1200
        self.state = "draft"
        try validate()
    }

    public static func validateName(_ name: String) throws {
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            throw UVError("VM names must be 1–64 ASCII letters, numbers, underscores or hyphens, starting with a letter or number.")
        }
    }

    public func validate() throws {
        try Self.validateName(name)
        guard schemaVersion == 1 else { throw UVError("Unsupported configuration version \(schemaVersion).") }
        guard guest == "macOS", state == "draft" else { throw UVError("Unsupported guest or configuration state.") }
        guard (1...1024).contains(cpuCount) else { throw UVError("CPU count must be between 1 and 1024.") }
        guard (4096...16_777_216).contains(memoryMiB) else { throw UVError("Memory must be between 4096 and 16777216 MiB.") }
        guard (20...1_048_576).contains(diskGiB) else { throw UVError("Disk must be between 20 and 1048576 GiB.") }
        guard (640...8192).contains(displayWidth), (480...8192).contains(displayHeight) else {
            throw UVError("Invalid display dimensions.")
        }
    }
}
