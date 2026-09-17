import Foundation
import Virtualization

public struct HostCapabilities: Codable {
    public let hardwareModel: String
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
        var length = 0
        var hardware = "unavailable"
        if sysctlbyname("hw.model", nil, &length, nil, 0) == 0, length > 0 {
            var buffer = [CChar](repeating: 0, count: length)
            if sysctlbyname("hw.model", &buffer, &length, nil, 0) == 0 { hardware = String(cString: buffer) }
        }
        return HostCapabilities(hardwareModel: hardware, architecture: architecture,
                                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                cpuCount: ProcessInfo.processInfo.processorCount,
                                memoryMiB: ProcessInfo.processInfo.physicalMemory / 1_048_576,
                                virtualizationSupported: VZVirtualMachine.isSupported)
    }
}
