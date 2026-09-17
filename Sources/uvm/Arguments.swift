import Foundation
import UVCore

struct Arguments {
    var positional: [String] = []
    var options: [String: [String]] = [:]
    init(_ args: [String], values: Set<String> = [], flags: Set<String> = [], repeated: Set<String> = []) throws {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                let pair = arg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let key = pair[0]
                guard options[key] == nil || repeated.contains(key) else { throw UVError("Repeated option: \(key)") }
                if flags.contains(key), pair.count == 1 { options[key] = ["true"] }
                else if values.contains(key) {
                    let value: String
                    if pair.count == 2 { value = pair[1] }
                    else { i += 1; guard i < args.count, !args[i].hasPrefix("--") else { throw UVError("Missing value for \(key)") }; value = args[i] }
                    options[key, default: []].append(value)
                } else { throw UVError("Unknown option: \(key)") }
            } else { positional.append(arg) }
            i += 1
        }
    }
    func require(_ count: Int) throws {
        guard positional.count == count else { throw UVError("Expected \(count) positional argument(s); run uvm help.") }
    }
    func value(_ name: String) -> String? { options[name]?.first }
    func int(_ name: String) throws -> Int? {
        guard let text = value(name) else { return nil }
        guard let value = Int(text) else { throw UVError("\(name) must be an integer.") }
        return value
    }
    func model() throws -> VMConfiguration {
        try require(1)
        return try VMConfiguration(name: positional[0], cpuCount: int("--cpu") ?? 4, memoryMiB: int("--memory") ?? 4096, diskGiB: int("--disk") ?? 64, guest: value("--linux") == nil ? "macOS" : "linux")
    }
}
