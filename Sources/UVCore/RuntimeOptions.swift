import Foundation
import Virtualization

public struct DirectoryMount {
    public let name: String
    public let url: URL
    public let readOnly: Bool
    public init(_ specification: String) throws {
        let parts = specification.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw UVError("Share syntax: NAME=PATH[:ro|:rw]") }
        try VMConfiguration.validateName(parts[0])
        name = parts[0]
        var path = parts[1]
        readOnly = !path.hasSuffix(":rw")
        if path.hasSuffix(":ro") || path.hasSuffix(":rw") { path.removeLast(3) }
        url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw UVError("Shared path must be a directory.") }
    }
}

public struct RuntimeOptions {
    public var directories: [DirectoryMount] = []
    public var bridge: String?
    public var audio = false
    public var clipboard = false
    public var additionalDisks: [URL] = []
    public var serial = false
    public var rosetta = false
    public init() {}
}

@MainActor
extension VirtualMachineFactory {
    static func apply(_ options: RuntimeOptions, to configuration: VZVirtualMachineConfiguration) throws {
        if let bridge = options.bridge {
            guard let interface = VZBridgedNetworkInterface.networkInterfaces.first(where: { $0.identifier == bridge }) else {
                throw UVError("Bridged interface '\(bridge)' is unavailable. Bridging also requires Apple's vm.networking entitlement.")
            }
            configuration.networkDevices.first?.attachment = VZBridgedNetworkDeviceAttachment(interface: interface)
        }
        if !options.directories.isEmpty {
            var shares: [String: VZSharedDirectory] = [:]
            for mount in options.directories {
                guard shares[mount.name] == nil else { throw UVError("Duplicate share name: \(mount.name)") }
                shares[mount.name] = VZSharedDirectory(url: mount.url, readOnly: mount.readOnly)
            }
            let device = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
            device.share = VZMultipleDirectoryShare(directories: shares)
            configuration.directorySharingDevices = [device]
        }
        if options.audio {
            let audio = VZVirtioSoundDeviceConfiguration()
            let output = VZVirtioSoundDeviceOutputStreamConfiguration()
            output.sink = VZHostAudioOutputStreamSink()
            audio.streams = [output]
            configuration.audioDevices = [audio]
        }
        if options.clipboard {
            let console = VZVirtioConsoleDeviceConfiguration()
            let port = VZVirtioConsolePortConfiguration()
            port.name = "com.redhat.spice.0"
            let agent = VZSpiceAgentPortAttachment()
            agent.sharesClipboard = true
            port.attachment = agent
            console.ports[0] = port
            configuration.consoleDevices = [console]
        }
        for disk in options.additionalDisks {
            try requireRegularFile(disk)
            let attachment = try VZDiskImageStorageDeviceAttachment(url: disk, readOnly: true)
            configuration.storageDevices.append(VZUSBMassStorageDeviceConfiguration(attachment: attachment))
        }
    }
}
