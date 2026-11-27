#if os(iOS)
import Foundation
import Security

/// One application-scoped item keeps a password bound to the tested destination.
/// This database is not a source for MigrationExecutor.
struct WebDAVConnectionStore {
    enum StorageError: Error { case unavailable }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.lingion.sleepy") + ".webdav",
         kSecAttrAccount as String: "manual-backup-v1",
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> WebDAVConnection? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StorageError.unavailable }
        return try JSONDecoder().decode(WebDAVConnection.self, from: data)
    }

    func save(_ connection: WebDAVConnection) throws {
        let data = try JSONEncoder().encode(connection)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StorageError.unavailable }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw StorageError.unavailable }
    }

    func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.unavailable }
    }
}
#endif
