import Foundation

public enum UVLog {
    public static func emit(_ message: String, level: String = "info") {
        let output: Data
        if ProcessInfo.processInfo.environment["UVM_LOG_FORMAT"] == "json" {
            let record = ["time": ISO8601DateFormatter().string(from: Date()), "level": level, "message": message]
            output = ((try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])) ?? Data()) + Data([10])
        } else { output = Data((message + "\n").utf8) }
        FileHandle.standardError.write(output)
    }
}
