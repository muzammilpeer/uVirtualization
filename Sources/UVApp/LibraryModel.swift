import SwiftUI
import UVCore
import AppKit

@MainActor
final class LibraryModel: ObservableObject {
    static let shared = LibraryModel()
    var store = VMStore(root: VMStore.defaultRoot)
    @Published var machines: [VMConfiguration] = []
    @Published var selection: String?
    @Published var statuses: [String: String] = [:]
    @Published var progress = ""
    @Published var busy = false
    @Published var canCancelInstallation = false
    @Published var error: String?
    private var runners: [String: VMRunner] = [:]
    private var installer: MacInstaller?
    var hasActiveWork: Bool { busy || !runners.isEmpty }

    func chooseStorage(_ url: URL) {
        guard !hasActiveWork else { error = "Stop active VMs and finish installation before changing storage."; return }
        store = VMStore(root: url)
        selection = nil
        refresh()
    }
    func refresh() {
        do {
            machines = try store.list()
            for machine in machines { statuses[machine.name] = try RuntimeControl.status(store: store, name: machine.name).state }
        } catch { self.error = error.localizedDescription }
    }
    func report(_ message: String) { progress = message }
    func create(name: String, linux: Bool, ipsw: String, cpu: Int, memory: Int, disk: Int) {
        guard !busy else { return }
        busy = true
        progress = "Preparing virtual machine…"
        Task {
            defer { busy = false; installer = nil; canCancelInstallation = false; refresh() }
            do {
                let model = try VMConfiguration(name: name, cpuCount: cpu, memoryMiB: memory, diskGiB: disk, guest: linux ? "linux" : "macOS")
                if linux { try LinuxInstaller.create(store: store, model: model) }
                else {
                    let installer = MacInstaller()
                    self.installer = installer
                    canCancelInstallation = true
                    try await installer.create(store: store, model: model, ipsw: ipsw) { message in
                        Task { @MainActor in self.report(message) }
                    }
                }
                selection = name
                progress = linux ? "EFI machine created. Use Run with ISO to install Linux." : "macOS installed. Start the VM to finish Setup Assistant."
            } catch { self.error = error.localizedDescription; progress = "Creation did not complete." }
        }
    }
    func cancelInstallation() { installer?.cancel() }
    func start(_ name: String, iso: URL? = nil, share: String? = nil, audio: Bool = false, clipboard: Bool = false) {
        if let runner = runners[name] { runner.showWindow(); return }
        do {
            var options = RuntimeOptions()
            if let iso { options.additionalDisks = [iso] }
            if let share { options.directories = [try DirectoryMount(share)] }
            options.audio = audio; options.clipboard = clipboard
            let runner = try VMRunner(store: store, name: name, options: options)
            runners[name] = runner
            Task {
                defer { runners[name] = nil; refresh() }
                do { try await runner.run() } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
    func control(_ name: String, _ command: String) {
        Task {
            do { try await RuntimeControl.send(store: store, name: name, command: command); refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
    func remove(_ name: String) {
        do { try store.delete(name); selection = nil; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func clone(_ name: String, to destination: String) {
        do { try store.clone(name, to: destination); selection = destination; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func configure(_ name: String, cpu: Int, memory: Int, disk: Int, width: Int, height: Int) {
        do { try store.configure(name, cpu: cpu, memory: memory, disk: disk, width: width, height: height); refresh() }
        catch { self.error = error.localizedDescription }
    }
    func importArchive(_ url: URL, name: String) {
        guard !busy else { return }
        busy = true; progress = "Importing and verifying archive…"
        let store = store
        Task {
            defer { busy = false; refresh() }
            do {
                try await Task.detached { try VMArchive.importVM(store: store, from: url, name: name) }.value
                selection = name; progress = "Import complete."
            } catch { self.error = error.localizedDescription }
        }
    }
}
