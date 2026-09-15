import Foundation
import Virtualization

@MainActor
public enum LinuxInstaller {
    /// Prepares an EFI machine; the user installs their distribution from an ARM64 ISO at first boot.
    public static func create(store: VMStore, model: VMConfiguration) throws {
        guard VZVirtualMachine.isSupported else { throw UVError("Virtualization is unavailable; use the signed executable on Apple silicon.") }
        let lock = try store.lock(model.name); defer { lock.unlock() }
        let stage = try store.stage(model.name)
        defer { try? FileManager.default.removeItem(at: stage) }
        var model = model
        model.guest = "linux"
        model.state = "ready"
        model.macAddress = VZMACAddress.randomLocallyAdministered().string
        _ = try VZEFIVariableStore(creatingVariableStoreAt: stage.appendingPathComponent("efi.bin"))
        try SparseDisk.create(at: stage.appendingPathComponent("disk.img"), bytes: UInt64(model.diskGiB) * 1_073_741_824)
        _ = try VirtualMachineFactory.configuration(model, directory: stage)
        try store.save(model, at: stage)
        try store.publish(stage, name: model.name)
    }
}
