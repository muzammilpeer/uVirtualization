import AppKit
import Virtualization

@MainActor
public final class VMRunner: NSObject, VZVirtualMachineDelegate, NSWindowDelegate {
    public let machine: VZVirtualMachine
    public let name: String
    private let ownership: FileLock
    private let controlDirectory: URL
    private let session = UUID().uuidString
    private var window: NSWindow?
    private var stopped = false
    private var failure: Error?
    private var controlTask: Task<Void, Never>?

    public init(store: VMStore, name: String) throws {
        self.name = name
        ownership = try store.lock(name)
        let model = try store.load(name)
        guard model.state == "ready" else { throw UVError("VM is a draft; install a guest first.") }
        machine = VZVirtualMachine(configuration: try VirtualMachineFactory.configuration(model, directory: store.directory(name)))
        controlDirectory = try RuntimeControl.directory(store: store, name: name)
        super.init()
        machine.delegate = self
        try FileManager.default.createDirectory(at: controlDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Only the owner can clean leftovers from an earlier runtime session.
        for item in try FileManager.default.contentsOfDirectory(at: controlDirectory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    public func run(headless: Bool = false) async throws {
        defer {
            controlTask?.cancel()
            window?.delegate = nil
            window?.close()
            try? FileManager.default.removeItem(at: controlDirectory.appendingPathComponent("status.json"))
            ownership.unlock()
        }
        try writeStatus("starting")
        try await machine.start()
        try writeStatus("running")
        if !headless { showWindow() }
        controlTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processRequests()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        while !stopped {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if let failure { throw failure }
    }

    public func control(_ command: String) async throws {
        switch command {
        case "pause":
            guard machine.canPause else { throw UVError("VM cannot pause in its current state.") }
            try await machine.pause()
            try writeStatus("paused")
        case "resume":
            guard machine.canResume else { throw UVError("VM cannot resume in its current state.") }
            try await machine.resume()
            try writeStatus("running")
        case "stop":
            guard machine.canRequestStop else { throw UVError("Guest cannot accept shutdown; resume it or use --force.") }
            try machine.requestStop()
            try writeStatus("stopping")
        case "force-stop":
            guard machine.canStop else { throw UVError("VM cannot stop in its current state.") }
            try await machine.stop()
            stopped = true
        default: throw UVError("Unknown runtime command.")
        }
    }

    private func writeStatus(_ state: String) throws {
        try JSONEncoder().encode(RuntimeStatus(name: name, state: state, processID: getpid(), session: session))
            .write(to: controlDirectory.appendingPathComponent("status.json"), options: .atomic)
    }
    private func processRequests() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: controlDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "request" {
            let reply = file.deletingPathExtension().appendingPathExtension("reply")
            var message = ""
            do {
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 4096 else { throw UVError("Invalid control request.") }
                let request = try JSONDecoder().decode(ControlRequest.self, from: Data(contentsOf: file))
                guard request.session == session, request.id == file.deletingPathExtension().lastPathComponent else { throw UVError("Expired control request.") }
                try await control(request.command)
            } catch { message = error.localizedDescription }
            try? Data(message.utf8).write(to: reply, options: .atomic)
            try? FileManager.default.removeItem(at: file)
        }
    }
    public func showWindow() {
        let view = VZVirtualMachineView()
        view.virtualMachine = machine
        view.capturesSystemKeys = true
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = name
        window.contentView = view
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task {
            do { try await control("stop") }
            catch { NSAlert(error: error).runModal() }
        }
        return false
    }
    nonisolated public func guestDidStop(_ virtualMachine: VZVirtualMachine) { Task { @MainActor in self.stopped = true } }
    nonisolated public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        Task { @MainActor in self.failure = error; self.stopped = true }
    }
}
