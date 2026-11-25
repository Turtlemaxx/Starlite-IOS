import Foundation
import Security

/// Where things are kept.
enum Storage {
    /// Settings and the library (not visible in Files).
    static var support: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Starlite", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Your songs: visible in the Files app (On My iPhone → Starlite).
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Covers taken out of local files.
    static var covers: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// The demo for screenshots (launch argument -StarliteDemo YES) never saves.
    static var demo: Bool { UserDefaults.standard.bool(forKey: "StarliteDemo") }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard !demo, let data = try? Data(contentsOf: support.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard !demo, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: support.appendingPathComponent(name), options: .atomic)
    }
}

/// Server logins live in the Keychain.
enum Keychain {
    private static let service = "io.github.turtlemaxx.starlite"

    static func set<T: Encodable>(_ value: T?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard !Storage.demo, let value, let data = try? JSONEncoder().encode(value) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard !Storage.demo else { return nil }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
