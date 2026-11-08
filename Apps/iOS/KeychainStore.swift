import Foundation
import Security
import CadenceCore

enum KeychainStore {
    static let service="com.bahachammakhi.cadence.credentials"
    static func load() -> ServerCredentials? {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"server",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess, let data=result as? Data else { return nil }
        return try? JSONDecoder().decode(ServerCredentials.self,from:data)
    }
    static func save(_ credentials: ServerCredentials) throws {
        let data=try JSONEncoder().encode(credentials)
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"server"]
        let attributes:[String:Any]=[kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status=SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
        if status==errSecItemNotFound {
            var add=query;attributes.forEach {add[$0.key]=$0.value}
            guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { throw CadenceError.message("Your sign-in couldn't be saved securely.") }
        } else if status != errSecSuccess { throw CadenceError.message("Your sign-in couldn't be saved securely.") }
    }
    static func clear() { SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"server"] as CFDictionary) }
}
