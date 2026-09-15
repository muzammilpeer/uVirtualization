import Foundation
import Security

public struct RegistryCredential: Codable {
    public var username: String
    public var password: String
    public init(username: String, password: String) { self.username = username; self.password = password }
}
public enum RegistryCredentials {
    private static func query(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.uvirtualization.registry", kSecAttrAccount as String: host]
    }
    public static func save(host: String, credential: RegistryCredential) throws {
        _ = try OCIReference(host + "/validation")
        guard !credential.username.isEmpty, !credential.password.isEmpty else { throw UVError("Username/password must not be empty.") }
        let data = try JSONEncoder().encode(credential)
        let result = SecItemUpdate(query(host) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query(host)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw UVError("Keychain save failed (\(added)).") }
        } else if result != errSecSuccess { throw UVError("Keychain update failed (\(result)).") }
    }
    public static func load(host: String) throws -> RegistryCredential? {
        let env = ProcessInfo.processInfo.environment
        if env["UVM_REGISTRY_HOST"] == host, let user = env["UVM_REGISTRY_USERNAME"], let pass = env["UVM_REGISTRY_PASSWORD"] {
            return RegistryCredential(username: user, password: pass)
        }
        var query = query(host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw UVError("Keychain credentials unavailable (\(status)). Unlock Keychain or use host-scoped environment credentials.") }
        return try JSONDecoder().decode(RegistryCredential.self, from: data)
    }
    public static func delete(host: String) throws {
        let result = SecItemDelete(query(host) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw UVError("Keychain removal failed (\(result)).") }
    }
}
