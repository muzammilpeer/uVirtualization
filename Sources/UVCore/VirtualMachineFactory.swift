import Foundation
import Virtualization

@MainActor
public enum VirtualMachineFactory {
    public static func configuration(_ model: VMConfiguration, directory: URL, options: RuntimeOptions = RuntimeOptions()) throws -> VZVirtualMachineConfiguration {
        try model.validate()
        guard VZVirtualMachine.isSupported else { throw UVError("Virtualization is unavailable. Run the signed binary on an Apple silicon host.") }
        let config = VZVirtualMachineConfiguration()
        guard model.cpuCount >= max(model.minimumCPUCount ?? 1, VZVirtualMachineConfiguration.minimumAllowedCPUCount),
              model.cpuCount <= VZVirtualMachineConfiguration.maximumAllowedCPUCount else { throw UVError("CPU count is outside guest/host limits.") }
        let memory = UInt64(model.memoryMiB) * 1_048_576
        guard memory >= max(UInt64(model.minimumMemoryMiB ?? 0) * 1_048_576, VZVirtualMachineConfiguration.minimumAllowedMemorySize),
              memory <= VZVirtualMachineConfiguration.maximumAllowedMemorySize else { throw UVError("Memory is outside guest/host limits.") }
        config.cpuCount = model.cpuCount
        config.memorySize = memory
        if model.guest == "macOS" {
        #if arch(arm64)
        let platform = VZMacPlatformConfiguration()
        guard let hardware = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: directory.appendingPathComponent("hardware.bin"))), hardware.isSupported,
              let identifier = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: directory.appendingPathComponent("machine.bin"))) else {
            throw UVError("Missing or incompatible Mac platform identity.")
        }
        platform.hardwareModel = hardware
        platform.machineIdentifier = identifier
        platform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: directory.appendingPathComponent("nvram.bin"))
        config.platform = platform
        config.bootLoader = VZMacOSBootLoader()
        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: model.displayWidth, heightInPixels: model.displayHeight, pixelsPerInch: 80)]
        config.graphicsDevices = [graphics]
        #else
        throw UVError("macOS guests require Apple silicon.")
        #endif
        } else {
            let platform = VZGenericPlatformConfiguration()
            config.platform = platform
            let boot = VZEFIBootLoader()
            boot.variableStore = VZEFIVariableStore(url: directory.appendingPathComponent("efi.bin"))
            config.bootLoader = boot
            let graphics = VZVirtioGraphicsDeviceConfiguration()
            graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: model.displayWidth, heightInPixels: model.displayHeight)]
            config.graphicsDevices = [graphics]
            config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
            if options.serial {
                let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
                serial.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: .standardInput, fileHandleForWriting: .standardOutput)
                config.serialPorts = [serial]
            }
        }
        let attachment = try VZDiskImageStorageDeviceAttachment(url: directory.appendingPathComponent("disk.img"), readOnly: false)
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        if let address = model.macAddress {
            guard let mac = VZMACAddress(string: address) else { throw UVError("Invalid MAC address.") }
            network.macAddress = mac
        }
        config.networkDevices = [network]
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        try apply(options, to: config)
        if options.rosetta {
            guard model.guest == "linux" else { throw UVError("Rosetta sharing is for Linux guests.") }
            #if arch(arm64)
            guard VZLinuxRosettaDirectoryShare.availability == .installed else { throw UVError("Rosetta is not installed. Run uvm install-rosetta before using --rosetta.") }
            let device = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
            device.share = try VZLinuxRosettaDirectoryShare()
            config.directorySharingDevices.append(device)
            #else
            throw UVError("Rosetta requires Apple silicon.")
            #endif
        }
        try config.validate()
        return config
    }
}
