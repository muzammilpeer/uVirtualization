import Foundation

public struct RuntimeStatus: Codable {
    public var name: String
    public var state: String
    public var processID: Int32
    public var session: String
}

public struct ControlRequest: Codable {
    public var id: String
    public var session: String
    public var command: String
}

public enum RuntimeControl {
    public static func directory(store: VMStore, name: String) throws -> URL {
        try VMConfiguration.validateName(name)
        return store.root.appendingPathComponent(".runtime/" + name)
    }
    public static func status(store: VMStore, name: String) throws -> RuntimeStatus {
        _ = try store.load(name)
        if let lock = try? store.lock(name) {
            lock.unlock()
            return RuntimeStatus(name: name, state: "stopped", processID: 0, session: "")
        }
        let url = try directory(store: store, name: name).appendingPathComponent("status.json")
        guard let data = try? Data(contentsOf: url), let status = try? JSONDecoder().decode(RuntimeStatus.self, from: data) else {
            return RuntimeStatus(name: name, state: "busy", processID: 0, session: "")
        }
        return status
    }
    public static func send(store: VMStore, name: String, command: String, timeout: Double = 30) async throws {
        guard ["stop", "force-stop", "pause", "resume"].contains(command) else { throw UVError("Invalid lifecycle command.") }
        let state = try status(store: store, name: name)
        guard !state.session.isEmpty else { throw UVError("VM is not accepting runtime commands (\(state.state)).") }
        let request = ControlRequest(id: UUID().uuidString, session: state.session, command: command)
        let dir = try directory(store: store, name: name)
        let requestURL = dir.appendingPathComponent(request.id + ".request")
        let replyURL = dir.appendingPathComponent(request.id + ".reply")
        defer { try? FileManager.default.removeItem(at: requestURL); try? FileManager.default.removeItem(at: replyURL) }
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: replyURL) {
                let error = String(decoding: data, as: UTF8.self)
                if !error.isEmpty { throw UVError(error) }
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw UVError("Runtime command timed out. Check uvm status; the request may already have been accepted.")
    }
}
