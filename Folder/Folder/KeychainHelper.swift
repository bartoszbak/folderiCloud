import Foundation
import Security

enum KeychainHelper {
    private static let account = "wordpress_access_token"
    static let appGroup = "group.com.bartbak.fastapp.folder"

    static func saveToken(_ token: String, accessGroup: String? = nil) {
        guard let data = token.data(using: .utf8) else { return }

        var query = baseQuery(accessGroup: accessGroup)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData] = data
        SecItemAdd(query as CFDictionary, nil)

        // Mirror to shared UserDefaults so the Share Extension can read it
        UserDefaults(suiteName: appGroup)?.set(token, forKey: "shared_token")
    }

    static func loadToken(accessGroup: String? = nil) -> String? {
        var query = baseQuery(accessGroup: accessGroup)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func deleteToken(accessGroup: String? = nil) {
        SecItemDelete(baseQuery(accessGroup: accessGroup) as CFDictionary)
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: "shared_token")
    }

    private static func baseQuery(accessGroup: String?) -> [CFString: Any] {
        var q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.bartbak.fastapp.Folder",
            kSecAttrAccount: account,
        ]
        if let group = accessGroup {
            q[kSecAttrAccessGroup] = group
        }
        return q
    }
}
