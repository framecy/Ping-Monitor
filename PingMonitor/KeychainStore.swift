import Foundation
import Security

/// Keychain 封装：只用于存放凭据类敏感数据。
///
/// 注意：不要把这些值写进 `ConfigManager` 的 JSON —— 那些文件是
/// `~/Library/Application Support/PingMonitor/` 下的明文，任何进程都能读。
enum KeychainStore {
    /// 钥匙串 service 名，与 bundle id 对齐，便于用户在「钥匙串访问」中检索。
    private static let service = "com.pingmonitor.app"

    enum Account: String {
        case tailscaleOAuthClientID = "tailscale.oauth.client_id"
        case tailscaleOAuthClientSecret = "tailscale.oauth.client_secret"
    }

    @discardableResult
    static func save(_ value: String, for account: Account) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]

        // 先尝试更新，不存在再新增，避免 errSecDuplicateItem。
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func load(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func has(_ account: Account) -> Bool {
        load(account)?.isEmpty == false
    }
}
