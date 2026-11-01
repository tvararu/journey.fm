import Foundation
import Security

public enum SessionStore {
    public static func load() -> Session? {
        read("jellyfin").flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    public static func save(_ session: Session) throws {
        try write("jellyfin", JSONEncoder().encode(session))
    }

    public static func clear() {
        SecItemDelete(query("jellyfin") as CFDictionary)
    }

    public static func deviceId() -> String {
        if let data = read("device"), let id = String(data: data, encoding: .utf8) { return id }
        let id = UUID().uuidString
        try? write("device", Data(id.utf8))
        return id
    }

    static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "fm.journey.session",
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> Data? {
        var item: CFTypeRef?
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    static func write(_ account: String, _ data: Data) throws {
        SecItemDelete(query(account) as CFDictionary)
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
