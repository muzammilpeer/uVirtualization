import Foundation
import Network
import CryptoKit

public struct APIRequest {
    public let method: String
    public let path: String
    public let authorization: String

    public static func parse(_ data: Data) throws -> APIRequest {
        guard data.count <= 16_384, let text = String(data: data, encoding: .utf8), text.hasSuffix("\r\n\r\n") else { throw UVError("Invalid HTTP request.") }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ").map(String.init)
        guard first.count == 3, ["GET", "POST"].contains(first[0]), first[2] == "HTTP/1.1",
              first[1].hasPrefix("/v1/"), !first[1].contains("%"), !first[1].contains("?") else { throw UVError("Unsupported API request.") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw UVError("Malformed HTTP header.") }
            let key = String(line[..<colon]).lowercased()
            guard headers[key] == nil else { throw UVError("Duplicate HTTP header.") }
            headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, headers["content-length"] == nil || headers["content-length"] == "0" else { throw UVError("API requests do not accept bodies.") }
        return APIRequest(method: first[0], path: first[1], authorization: headers["authorization"] ?? "")
    }
    public func authorized(token: String) -> Bool {
        let lhs = Array(SHA256.hash(data: Data(authorization.utf8)))
        let rhs = Array(SHA256.hash(data: Data(("Bearer " + token).utf8)))
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }
}

@MainActor
public final class ControlAPIServer {
    private let store: VMStore
    private let token: String
    private let listener: NWListener
    private var connections: [UUID: NWConnection] = [:]
    private var runners: [String: VMRunner] = [:]
    private var failure: Error?
    private var shuttingDown = false

    public init(store: VMStore, port: UInt16, tokenFile: URL) throws {
        guard port >= 1024 else { throw UVError("Use a nonprivileged port (1024–65535).") }
        let token = try Self.readToken(from: tokenFile)
        self.store = store; self.token = token
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
    }
    public static func readToken(from tokenFile: URL) throws -> String {
        try requireRegularFile(tokenFile)
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenFile.path)
        guard ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw UVError("API token file must be owned by you and private (chmod 600).") }
        let token = try String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...256).contains(token.utf8.count), !token.contains(where: { $0.isWhitespace }) else { throw UVError("Use a randomly generated API token of 32–256 characters.") }
        return token
    }
    public func run() async throws {
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in if case .failed(let error) = state { self?.failure = error } }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
        defer { listener.cancel(); connections.values.forEach { $0.cancel() } }
        while failure == nil {
            if Task.isCancelled, !shuttingDown {
                shuttingDown = true
                for runner in runners.values { try? await runner.control("stop") }
            }
            if shuttingDown && runners.isEmpty { return }
            // Cancellation must not destroy guests still shutting down. Keep the control API available.
            await withCheckedContinuation { continuation in DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { continuation.resume() } }
        }
        throw failure!
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 64 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.connections.removeValue(forKey: id)?.cancel()
        }
        receive(connection, id: id, accumulated: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var data = accumulated
                if let bytes { data.append(bytes) }
                if error != nil || data.count > 16_384 { self.respond(connection, id: id, code: 400, body: Data("{}".utf8)); return }
                if data.range(of: Data("\r\n\r\n".utf8)) != nil {
                    do {
                        let request = try APIRequest.parse(data)
                        guard request.authorized(token: self.token) else { self.respond(connection, id: id, code: 401, body: Data("{}".utf8)); return }
                        let response = try await self.route(request)
                        self.respond(connection, id: id, code: 200, body: response)
                    } catch {
                        let body = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data("{}".utf8)
                        self.respond(connection, id: id, code: 400, body: body)
                    }
                } else if complete { self.respond(connection, id: id, code: 400, body: Data("{}".utf8)) }
                else { self.receive(connection, id: id, accumulated: data) }
            }
        }
    }
    private func route(_ request: APIRequest) async throws -> Data {
        let encoder = JSONEncoder()
        if request.method == "GET", request.path == "/v1/host" { return try encoder.encode(HostCapabilities.current()) }
        if request.method == "GET", request.path == "/v1/vms" { return try encoder.encode(store.list()) }
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "v1", parts[1] == "vms" else { throw UVError("Unknown API route.") }
        let name = parts[2]
        try VMConfiguration.validateName(name)
        if request.method == "GET", parts[3] == "status" { return try encoder.encode(RuntimeControl.status(store: store, name: name)) }
        guard request.method == "POST" else { throw UVError("Unsupported API method.") }
        if parts[3] == "start" {
            guard !shuttingDown, runners[name] == nil else { throw UVError("Server is shutting down or VM is already owned.") }
            let runner = try VMRunner(store: store, name: name)
            runners[name] = runner
            Task {
                defer { runners[name] = nil }
                do { try await runner.run(headless: true) }
                catch { FileHandle.standardError.write(Data("VM \(name): \(error.localizedDescription)\n".utf8)) }
            }
            return try JSONSerialization.data(withJSONObject: ["name": name, "state": "starting"])
        }
        guard ["stop", "force-stop", "pause", "resume", "suspend"].contains(parts[3]) else { throw UVError("Unknown lifecycle action.") }
        try await RuntimeControl.send(store: store, name: name, command: parts[3])
        return try encoder.encode(RuntimeControl.status(store: store, name: name))
    }
    private func respond(_ connection: NWConnection, id: UUID, code: Int, body: Data) {
        let reason = code == 200 ? "OK" : code == 401 ? "Unauthorized" : "Bad Request"
        var response = Data("HTTP/1.1 \(code) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.connections.removeValue(forKey: id); connection.cancel() }
        })
    }
}
