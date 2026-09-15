import Foundation
import Virtualization

public struct HostCapabilities: Codable {
    public let architecture: String
    public let operatingSystem: String
    public let cpuCount: Int
    public let memoryMiB: UInt64
    public let virtualizationSupported: Bool

    public static func current() -> HostCapabilities {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unsupported"
        #endif
        return HostCapabilities(architecture: architecture,
                                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                cpuCount: ProcessInfo.processInfo.processorCount,
                                memoryMiB: ProcessInfo.processInfo.physicalMemory / 1_048_576,
                                virtualizationSupported: VZVirtualMachine.isSupported)
    }
}
