import Foundation
import UVCore

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func run() throws {
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
  doctor                         Report host capabilities as JSON
  init NAME [--cpu N] [--memory MiB] [--disk GiB]
                                 Create a draft configuration (no guest installed)
  list                           List draft configurations as JSON
  inspect NAME                   Print a configuration as JSON
  version                        Print version
  help                           Show help

Storage: UVM_HOME or ~/.uvm
macOS installation, clone and run are planned; this preview cannot boot a VM.
"""

do { try run() }
catch {
    FileHandle.standardError.write(Data("uvm: \(error.localizedDescription)\n".utf8))
    exit(1)
}
