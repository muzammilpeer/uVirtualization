import Foundation
import Virtualization

@MainActor
public final class MacInstaller {
    private var cancelled = false
    private var installer: VZMacOSInstaller?
    private var downloadTask: Task<URL, Error>?
    public init() {}
    public func cancel() { cancelled = true; installer?.progress.cancel(); downloadTask?.cancel() }

    public func create(store: VMStore, model: VMConfiguration, ipsw: String,
                       progress: @escaping (String) -> Void) async throws {
        #if arch(arm64)
        cancelled = false
        guard VZVirtualMachine.isSupported else { throw UVError("Virtualization is unavailable. Build and sign using scripts/sign.sh, then run .build/debug/uvm.") }
        let lock = try store.lock(model.name)
        defer { lock.unlock() }
        let stage = try store.stage(model.name)
        do {
            var imageURL = URL(fileURLWithPath: ipsw)
            if ipsw == "latest" {
                progress("Finding latest compatible macOS restore image")
                let latest = try await VZMacOSRestoreImage.latestSupported
                progress("Downloading restore image")
                let destination = stage.appendingPathComponent("restore.ipsw")
                let task = Task<URL, Error> {
                    let (temporary, response) = try await URLSession.shared.download(from: latest.url)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UVError("Restore image download failed.") }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    return destination
                }
                downloadTask = task
                imageURL = try await task.value
                downloadTask = nil
            }
            if cancelled { throw CancellationError() }
            let image = try await VZMacOSRestoreImage.image(from: imageURL)
            if cancelled { throw CancellationError() }
            guard let requirements = image.mostFeaturefulSupportedConfiguration else { throw UVError("This restore image is incompatible with the host.") }
            var ready = model
            ready.minimumCPUCount = requirements.minimumSupportedCPUCount
            ready.minimumMemoryMiB = Int((requirements.minimumSupportedMemorySize + 1_048_575) / 1_048_576)
            ready.cpuCount = max(ready.cpuCount, ready.minimumCPUCount!)
            ready.memoryMiB = max(ready.memoryMiB, ready.minimumMemoryMiB!)
            ready.macAddress = VZMACAddress.randomLocallyAdministered().string
            let available = try stage.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            guard available >= Int64(ready.diskGiB) * 1_073_741_824 else { throw UVError("Insufficient free space for the requested disk capacity.") }
            try requirements.hardwareModel.dataRepresentation.write(to: stage.appendingPathComponent("hardware.bin"), options: .atomic)
            try VZMacMachineIdentifier().dataRepresentation.write(to: stage.appendingPathComponent("machine.bin"), options: .atomic)
            _ = try VZMacAuxiliaryStorage(creatingStorageAt: stage.appendingPathComponent("nvram.bin"), hardwareModel: requirements.hardwareModel, options: [])
            try SparseDisk.create(at: stage.appendingPathComponent("disk.img"), bytes: UInt64(ready.diskGiB) * 1_073_741_824)
            let vm = VZVirtualMachine(configuration: try VirtualMachineFactory.configuration(ready, directory: stage))
            let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: imageURL)
            self.installer = installer
            defer { self.installer = nil }
            let observation = installer.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in
                progress("Installing macOS: \(Int(p.fractionCompleted * 100))%")
            }
            defer { observation.invalidate() }
            if cancelled { throw CancellationError() }
            try await installer.install()
            ready.state = "ready"
            try store.save(ready, at: stage)
            if ipsw == "latest" { try FileManager.default.removeItem(at: imageURL) }
            try store.publish(stage, name: ready.name)
            progress("Installation complete")
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: stage.appendingPathComponent("failure.txt"), options: .atomic)
            if cancelled || error is CancellationError { progress("Cancelled. Incomplete installation retained at \(stage.path)."); throw CancellationError() }
            throw UVError("\(error.localizedDescription)\nIncomplete installation retained at \(stage.path).")
        }
        #else
        throw UVError("macOS guests require Apple silicon.")
        #endif
    }
}

public enum SparseDisk {
    public static func create(at url: URL, bytes: UInt64) throws {
        guard bytes > 0, bytes <= UInt64(Int64.max) else { throw UVError("Invalid disk size.") }
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw UVError("Cannot create disk: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        guard ftruncate(fd, off_t(bytes)) == 0 else { throw UVError("Cannot size disk: \(String(cString: strerror(errno)))") }
    }
}
