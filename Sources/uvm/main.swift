import Foundation
import AppKit
import UVCore

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

@MainActor
func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let store = VMStore(root: VMStore.defaultRoot)
    guard let command = arguments.first else { print(help); return }
    let rest = Array(arguments.dropFirst())
    switch command {
    case "help", "--help", "-h":
        guard rest.isEmpty else { throw UVError("help takes no arguments.") }
        print(help)
    case "version", "--version":
        guard rest.isEmpty else { throw UVError("version takes no arguments.") }
        print("uvm 0.1.0-dev")
    case "doctor":
        guard rest.isEmpty else { throw UVError("doctor takes no arguments.") }
        let host = HostCapabilities.current()
        try printJSON(host)
        guard host.architecture == "arm64", host.virtualizationSupported else {
            throw UVError("Virtualization is unavailable to this process. Use an Apple silicon Mac and check host support, signing entitlements and execution restrictions.")
        }
    case "list":
        guard rest.isEmpty else { throw UVError("list takes no arguments.") }
        try printJSON(store.list())
    case "inspect":
        guard rest.count == 1 else { throw UVError("Usage: uvm inspect NAME") }
        try printJSON(store.load(rest[0]))
    case "run":
        guard rest.count >= 1, rest.count <= 2, rest.count == 1 || rest[1] == "--headless" else { throw UVError("Usage: uvm run NAME [--headless]") }
        let runner = try VMRunner(store: store, name: rest[0])
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { signalNumber -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { Task { try? await runner.control("stop") } }
            source.resume()
            return source
        }
        defer { signals.forEach { $0.cancel() } }
        try await runner.run(headless: rest.contains("--headless"))
    case "status":
        guard rest.count == 1 else { throw UVError("Usage: uvm status NAME") }
        try printJSON(RuntimeControl.status(store: store, name: rest[0]))
    case "stop", "pause", "resume":
        guard rest.count == 1 || (command == "stop" && rest.count == 2 && rest[1] == "--force") else { throw UVError("Usage: uvm \(command) NAME" + (command == "stop" ? " [--force]" : "")) }
        try await RuntimeControl.send(store: store, name: rest[0], command: rest.contains("--force") ? "force-stop" : command)
        try printJSON(RuntimeControl.status(store: store, name: rest[0]))
    case "create":
        guard rest.count == 3, rest[1] == "--from-ipsw" else { throw UVError("Usage: uvm create NAME --from-ipsw PATH|latest") }
        let installer = MacInstaller()
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler { installer.cancel() }
        interrupt.resume()
        defer { interrupt.cancel() }
        try await installer.create(store: store, model: VMConfiguration(name: rest[0]), ipsw: rest[2]) { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        try printJSON(store.load(rest[0]))
    case "init":
        guard let name = rest.first else { throw UVError("Usage: uvm init NAME [--cpu N] [--memory N] [--disk N]") }
        var values: [String: Int] = [:]
        var index = 1
        while index < rest.count {
            let key = rest[index]
            guard ["--cpu", "--memory", "--disk"].contains(key), index + 1 < rest.count,
                  let value = Int(rest[index + 1]), values[key] == nil else {
                throw UVError("Invalid or repeated option '\(key)'. Use --cpu N, --memory MiB, --disk GiB.")
            }
            values[key] = value
            index += 2
        }
        let configuration = try VMConfiguration(name: name, cpuCount: values["--cpu"] ?? 4,
                                                memoryMiB: values["--memory"] ?? 4096, diskGiB: values["--disk"] ?? 64)
        try store.create(configuration)
        try printJSON(configuration)
    default:
        throw UVError("Unknown command '\(command)'. Run uvm help for implemented commands.")
    }
}

let help = """
uVirtualization — Swift VM manager (foundation preview)

Usage: uvm COMMAND
  run NAME [--headless]           Run an installed guest
  status NAME                    Report runtime state
  stop NAME [--force]             Request shutdown or force stop
  pause NAME / resume NAME        Control execution
  create NAME --from-ipsw PATH|latest
                                 Install macOS from a restore image
  doctor                         Report host capabilities as JSON
  init NAME [--cpu N] [--memory MiB] [--disk GiB]
                                 Create a draft configuration (no guest installed)
  list                           List draft configurations as JSON
  inspect NAME                   Print a configuration as JSON
  version                        Print version
  help                           Show help

Storage: UVM_HOME or ~/.uvm
Use scripts/sign.sh before guest installation or execution.
"""

Task { @MainActor in
do { try await run(); exit(0) }
catch {
    FileHandle.standardError.write(Data("uvm: \(error.localizedDescription)\n".utf8))
    exit(1)
}

}
if CommandLine.arguments.dropFirst().first == "run", !CommandLine.arguments.contains("--headless") {
    NSApplication.shared.run()
} else {
    dispatchMain()
}
