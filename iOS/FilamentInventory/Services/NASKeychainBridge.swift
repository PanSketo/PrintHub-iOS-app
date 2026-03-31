import Foundation
import Security

/// Shared keychain helper — used by both the main app and the widget extension.
///
/// iOS guarantees that an app extension inherits the same default Keychain
/// access group as its containing app (same Team ID + bundle ID prefix).
/// No `keychain-access-groups` entitlement is required for this default group,
/// so this works even in sideloaded / re-signed builds.
enum NASKeychainBridge {

    private static let service = "PrintHubNASConfig"
    private static let account = "nas_credentials"

    // ── Write ─────────────────────────────────────────────────────────────────

    static func save(url: String, key: String) {
        let payload: [String: String] = ["url": url, "key": key]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        // Try updating an existing item first
        let findQuery = baseQuery()
        let updateAttrs: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(findQuery as CFDictionary, updateAttrs as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    static func load() -> (url: String, key: String)? {
        var readQuery = baseQuery()
        readQuery[kSecReturnData]  = true
        readQuery[kSecMatchLimit]  = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }

        // Try JSON decoding first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let url = json["url"], let key = json["key"] {
            return (url, key)
        }

        // Migration: fall back to legacy newline-delimited format, then re-save in JSON
        if let str = String(data: data, encoding: .utf8) {
            let parts = str.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let url   = parts.count > 0 ? String(parts[0]) : ""
            let key   = parts.count > 1 ? String(parts[1]) : ""
            save(url: url, key: key)  // re-save in new JSON format
            return (url, key)
        }

        return nil
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private static func baseQuery() -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
    }
}
