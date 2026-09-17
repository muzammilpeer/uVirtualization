import Foundation

public struct UVError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct VMConfiguration: Codable, Equatable {
    public var schemaVersion: Int
    public var name: String
    public var guest: String
    public var cpuCount: Int
    public var memoryMiB: Int
    public var diskGiB: Int
    public var displayWidth: Int
    public var displayHeight: Int
    public var state: String
    public var macAddress: String?
    public var minimumCPUCount: Int?
    public var minimumMemoryMiB: Int?

    public init(name: String, cpuCount: Int = 4, memoryMiB: Int = 4096, diskGiB: Int = 64, guest: String = "macOS") throws {
        self.schemaVersion = 1
        self.name = name
        self.guest = guest
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
        guard ["macOS", "linux"].contains(guest), ["draft", "ready"].contains(state) else { throw UVError("Unsupported guest or configuration state.") }
        guard (1...1024).contains(cpuCount) else { throw UVError("CPU count must be between 1 and 1024.") }
        guard ((guest == "macOS" ? 4096 : 512)...16_777_216).contains(memoryMiB) else { throw UVError("Memory must meet the guest minimum (macOS: 4096 MiB; Linux: 512 MiB) and not exceed 16777216 MiB.") }
        let minimumDiskGiB = guest == "macOS" ? 20 : 1
        guard (minimumDiskGiB...1_048_576).contains(diskGiB) else { throw UVError("Disk must be between \(minimumDiskGiB) and 1048576 GiB for \(guest).") }
        if let address = macAddress {
            guard address.range(of: "^(?:[a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$", options: .regularExpression) != nil else { throw UVError("Invalid MAC address.") }
        }
        if let minimumCPUCount { guard (1...1024).contains(minimumCPUCount) else { throw UVError("Invalid minimum CPU count.") } }
        if let minimumMemoryMiB { guard (1...16_777_216).contains(minimumMemoryMiB) else { throw UVError("Invalid minimum memory.") } }
        guard (640...8192).contains(displayWidth), (480...8192).contains(displayHeight) else {
            throw UVError("Invalid display dimensions.")
        }
    }
}
