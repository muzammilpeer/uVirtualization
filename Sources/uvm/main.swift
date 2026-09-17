import Foundation
import AppKit
import Virtualization
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
    case "repair":
        guard rest.isEmpty else { throw UVError("repair takes no arguments.") }
        try store.recoverRenames()
        try printJSON(store.list())
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
    case "inspect", "get":
        guard rest.count == 1 else { throw UVError("Usage: uvm inspect NAME") }
        try printJSON(store.load(rest[0]))
    case "serve":
        let args = try Arguments(rest, values: ["--port", "--token-file"])
        try args.require(0)
        guard let token = args.value("--token-file"), let port = UInt16(exactly: try args.int("--port") ?? 9022) else { throw UVError("Usage: uvm serve --token-file PATH [--port 9022]") }
        let server = try ControlAPIServer(store: store, port: port, tokenFile: URL(fileURLWithPath: token))
        FileHandle.standardError.write(Data("Control API bound to loopback port \(port).\n".utf8))
        try await server.run()
    case "fqn":
        guard rest.count == 1 else { throw UVError("Usage: uvm fqn REGISTRY/IMAGE:TAG") }
        let reference = try OCIReference(rest[0])
        let (_, digest) = try await RegistryClient(reference: reference).manifest()
        print(reference.host + "/" + reference.repository + "@" + digest)
    case "exec":
        guard let separator = rest.firstIndex(of: "--") else { throw UVError("Usage: uvm exec NAME --user USER -- COMMAND [ARG...]") }
        let args = try Arguments(Array(rest[..<separator]), values: ["--user", "--timeout"])
        try args.require(1)
        guard let user = args.value("--user") else { throw UVError("Specify --user for SSH execution.") }
        let ip = try await IPDiscovery.wait(store: store, name: args.positional[0], timeout: Double(try args.int("--timeout") ?? 30))
        try await GuestCommand.execute(address: ip, user: user, arguments: Array(rest.dropFirst(separator + 1)))
    case "completions":
        guard rest.count == 1 else { throw UVError("Usage: uvm completions bash|zsh|fish") }
        let commands = "create init clone run set get inspect list status login logout ip exec pull push import export prune rename stop pause resume suspend delete fqn doctor repair version help serve"
        switch rest[0] {
        case "bash": print("complete -W '\(commands)' uvm")
        case "zsh": print("#compdef uvm\n_arguments '1:command:(\(commands))' '*:file:_files'")
        case "fish": print("complete -c uvm -f -a '\(commands)'")
        default: throw UVError("Supported shells: bash, zsh, fish.")
        }
    case "run":
        let args = try Arguments(rest, values: ["--dir", "--bridge", "--disk"], flags: ["--headless", "--audio", "--clipboard", "--serial", "--rosetta"], repeated: ["--dir", "--disk"])
        try args.require(1)
        var options = RuntimeOptions()
        options.directories = try (args.options["--dir"] ?? []).map { try DirectoryMount($0) }
        options.bridge = args.value("--bridge")
        options.audio = args.value("--audio") != nil
        options.clipboard = args.value("--clipboard") != nil
        options.serial = args.value("--serial") != nil
        options.rosetta = args.value("--rosetta") != nil
        options.additionalDisks = (args.options["--disk"] ?? []).map { URL(fileURLWithPath: $0) }
        let runner = try VMRunner(store: store, name: args.positional[0], options: options)
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
    case "stop", "pause", "resume", "suspend":
        guard rest.count == 1 || (command == "stop" && rest.count == 2 && rest[1] == "--force") else { throw UVError("Usage: uvm \(command) NAME" + (command == "stop" ? " [--force]" : "")) }
        try await RuntimeControl.send(store: store, name: rest[0], command: rest.contains("--force") ? "force-stop" : command)
        try printJSON(RuntimeControl.status(store: store, name: rest[0]))
    case "login":
        let args = try Arguments(rest, values: ["--username"], flags: ["--password-stdin"])
        try args.require(1)
        guard let user = args.value("--username"), args.value("--password-stdin") != nil else { throw UVError("Usage: uvm login HOST --username USER --password-stdin") }
        let password = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .newlines)
        try RegistryCredentials.save(host: args.positional[0], credential: RegistryCredential(username: user, password: password))
    case "logout":
        guard rest.count == 1 else { throw UVError("Usage: uvm logout HOST") }
        try RegistryCredentials.delete(host: rest[0])
    case "push":
        guard rest.count == 2 else { throw UVError("Usage: uvm push NAME REGISTRY/IMAGE:TAG") }
        try await RegistryImages.push(store: store, name: rest[0], reference: OCIReference(rest[1])) { message in UVLog.emit(message) }
    case "prune":
        guard rest == ["--all"] else { throw UVError("Usage: uvm prune --all (removes cached registry data only)") }
        try RegistryImages.prune(store: store)
    case "image-info":
        guard rest.count == 1 else { throw UVError("Usage: uvm image-info REGISTRY/IMAGE:TAG") }
        let client = RegistryClient(reference: try OCIReference(rest[0]))
        let (manifest, digest) = try await client.manifest()
        FileHandle.standardError.write(Data((digest + "\n").utf8))
        try printJSON(manifest)
    case "pull":
        guard rest.count == 1 else { throw UVError("Usage: uvm pull REGISTRY/IMAGE:TAG") }
        let image = try await RegistryImages.pull(OCIReference(rest[0]), store: store) { message in UVLog.emit(message) }
        try printJSON(image)
    case "ip":
        let args = try Arguments(rest, values: ["--timeout"])
        try args.require(1)
        print(try await IPDiscovery.wait(store: store, name: args.positional[0], timeout: Double(try args.int("--timeout") ?? 30)))
    case "set":
        let args = try Arguments(rest, values: ["--cpu", "--memory", "--disk", "--width", "--height"])
        try args.require(1)
        try store.configure(args.positional[0], cpu: args.int("--cpu"), memory: args.int("--memory"), disk: args.int("--disk"), width: args.int("--width"), height: args.int("--height"))
        try printJSON(store.load(args.positional[0]))
    case "clone", "rename":
        let args = try Arguments(rest, flags: command == "clone" ? ["--discard-blobs"] : [])
        let rest = args.positional
        guard rest.count == 2 else { throw UVError("Usage: uvm \(command) SOURCE DESTINATION") }
        if command == "clone", rest[0].contains("/") {
            try await RegistryImages.clone(OCIReference(rest[0]), store: store, name: rest[1], keepBlobs: args.value("--discard-blobs") == nil) { message in UVLog.emit(message) }
        } else if command == "clone" { try store.clone(rest[0], to: rest[1]) }
        else { try store.rename(rest[0], to: rest[1]) }
        try printJSON(store.load(rest[1]))
    case "delete":
        guard rest.count == 1 else { throw UVError("Usage: uvm delete NAME") }
        try store.delete(rest[0])
    case "export":
        guard rest.count == 2 else { throw UVError("Usage: uvm export NAME FILE.uvma") }
        try VMArchive.export(store: store, name: rest[0], to: URL(fileURLWithPath: rest[1]))
    case "import":
        guard rest.count == 2 else { throw UVError("Usage: uvm import FILE.uvma NAME") }
        try VMArchive.importVM(store: store, from: URL(fileURLWithPath: rest[0]), name: rest[1])
        try printJSON(store.load(rest[1]))
    case "install-rosetta":
        guard rest.isEmpty else { throw UVError("install-rosetta takes no arguments.") }
        #if arch(arm64)
        try await VZLinuxRosettaDirectoryShare.installRosetta()
        #else
        throw UVError("Rosetta requires Apple silicon.")
        #endif
    case "create":
        let args = try Arguments(rest, values: ["--from-ipsw", "--cpu", "--memory", "--disk"], flags: ["--linux"])
        let model = try args.model()
        if args.value("--linux") != nil {
            guard args.value("--from-ipsw") == nil else { throw UVError("Choose --linux or --from-ipsw.") }
            try LinuxInstaller.create(store: store, model: model)
            try printJSON(store.load(model.name))
            return
        }
        guard let ipsw = args.value("--from-ipsw") else { throw UVError("Usage: uvm create NAME --from-ipsw PATH|latest") }
        let installer = MacInstaller()
        let interrupts = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { installer.cancel() }
            source.resume()
            return source
        }
        defer { interrupts.forEach { $0.cancel() } }
        try await installer.create(store: store, model: model, ipsw: ipsw) { message in
            UVLog.emit(message)
        }
        try printJSON(store.load(model.name))
    case "init":
        let args = try Arguments(rest, values: ["--cpu", "--memory", "--disk"])
        let model = try args.model()
        try store.create(model)
        try printJSON(model)
    default:
        throw UVError("Unknown command '\(command)'. Run uvm help for implemented commands.")
    }
}

let help = """
uVirtualization — Swift VM manager (development build)

Usage: uvm COMMAND
  set NAME [--cpu N] [--memory MiB] [--disk GiB] [--width N] [--height N]
  login HOST --username USER --password-stdin
  logout HOST
  push NAME REGISTRY/IMAGE:TAG    Publish a stopped VM
  prune --all                    Remove registry cache
  image-info REGISTRY/IMAGE:TAG   Inspect remote manifest
  pull REGISTRY/IMAGE:TAG         Cache a verified VM image
  clone SOURCE DESTINATION       Clone a stopped local VM
  rename SOURCE DESTINATION      Rename a stopped VM
  delete NAME                    Delete a stopped VM and its disks
  export NAME FILE.uvma           Export a checked archive
  import FILE.uvma NAME           Import with fresh identity
  ip NAME [--timeout SECONDS]     Discover NAT guest address
  run NAME [--headless] [--dir NAME=PATH:ro|:rw] [--bridge IFACE]
           [--audio] [--clipboard] [--disk READ_ONLY_IMAGE]
  status NAME                    Report runtime state
  stop NAME [--force]             Request shutdown or force stop
  pause NAME / resume NAME        Control execution
  suspend NAME                   Save state on compatible macOS 14+ guests
  create NAME --linux [--disk GiB]
                                 Prepare an ARM64 EFI guest for ISO installation
  install-rosetta                Install Apple Rosetta support for Linux guests
  create NAME --from-ipsw PATH|latest
                                 Install macOS from a restore image
  repair                         Recover journaled interrupted renames
  doctor                         Report host capabilities as JSON
  init NAME [--cpu N] [--memory MiB] [--disk GiB]
                                 Create a draft configuration (no guest installed)
  list                           List local VMs as JSON
  inspect NAME                   Print a configuration as JSON
  serve --token-file PATH [--port 9022]
                                 Start token-protected loopback control API
  fqn REGISTRY/IMAGE:TAG          Resolve an immutable image reference
  exec NAME --user USER -- COMMAND [ARG...]
                                 Execute over SSH using existing host trust
  completions bash|zsh|fish       Print shell completion script
  version                        Print version
  help                           Show help

Storage: UVM_HOME or ~/.uvm
Use scripts/sign.sh before guest installation or execution.
"""

let commandTask = Task { @MainActor in
do { try await run(); exit(0) }
catch let error as GuestExit { exit(error.status) }
catch {
    if ProcessInfo.processInfo.environment["UVM_JSON_ERRORS"] == "1" {
        let data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data()
        FileHandle.standardError.write(data + Data([10]))
    } else {
    FileHandle.standardError.write(Data("uvm: \(error.localizedDescription)\n".utf8))
    }
    exit(error is CancellationError ? 130 : 1)
}

}
var cancellationSignals: [DispatchSourceSignal] = []
if !["run", "create"].contains(CommandLine.arguments.dropFirst().first ?? "") {
    for number in [SIGINT, SIGTERM] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { commandTask.cancel() }
        source.resume()
        cancellationSignals.append(source)
    }
}
if CommandLine.arguments.dropFirst().first == "run", !CommandLine.arguments.contains("--headless") {
    NSApplication.shared.run()
} else if ["run", "create", "serve"].contains(CommandLine.arguments.dropFirst().first ?? "") {
    // Keep the main thread alive for Apple's virtualization and device event delivery.
    RunLoop.main.run()
} else {
    dispatchMain()
}
