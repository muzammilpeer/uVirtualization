import Foundation

public enum IPDiscovery {
    public static func address(in leases: String, mac: String, now: Date = Date()) -> String? {
        func normalized(_ value: String) -> String {
            value.lowercased().split(separator: ":").map { String(Int($0, radix: 16) ?? -1) }.joined(separator: ":")
        }
        for block in leases.components(separatedBy: "}").reversed() {
            var fields: [String: String] = [:]
            for line in block.components(separatedBy: .newlines) {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { fields[parts[0]] = parts[1] }
            }
            guard let hardware = fields["hw_address"]?.split(separator: ",").last,
                  normalized(String(hardware)) == normalized(mac), let ip = fields["ip_address"] else { continue }
            if let lease = fields["lease"], let expiration = UInt64(lease.replacingOccurrences(of: "0x", with: ""), radix: 16),
               expiration != 0, expiration < UInt64(now.timeIntervalSince1970) { continue }
            let octets = ip.split(separator: ".")
            if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) { return ip }
        }
        return nil
    }
    public static func wait(store: VMStore, name: String, timeout: Double = 30) async throws -> String {
        guard timeout.isFinite, (0...3600).contains(timeout) else { throw UVError("Timeout must be 0–3600 seconds.") }
        guard let mac = try store.load(name).macAddress else { throw UVError("VM has no network identity.") }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let leases = try String(contentsOfFile: "/var/db/dhcpd_leases", encoding: .utf8)
            if let address = address(in: leases, mac: mac) { return address }
            if Date() >= deadline { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        } while true
        throw UVError("No NAT DHCP address found within \(timeout) seconds. The guest must boot and request DHCP; bridged guests use their network's DHCP service.")
    }
}
