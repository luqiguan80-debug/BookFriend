import Foundation
import Security

/// API key 本地存储封装，绝不上传（PRD 4.5）
/// macOS：开发构建免签名，钥匙串 ACL 按签名认 App，每次编译都弹授权框；
///        本机自用直接存 UserDefaults，零打扰。
/// iOS：无弹窗问题，继续用 Keychain。
enum Keychain {
    #if os(macOS)
    static func set(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: "kc.\(key)")
    }

    static func get(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: "kc.\(key)")
    }

    static func delete(_ key: String) {
        UserDefaults.standard.removeObject(forKey: "kc.\(key)")
    }
    #else
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
    #endif
}
