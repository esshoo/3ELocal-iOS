import Foundation
import Combine
import CryptoKit
import Security

struct LocalSigningKeyMetadata: Codable, Hashable, Identifiable {
    let schemaVersion: Int
    let publisherID: String
    let publisherName: String
    let keyID: String
    let publicKey: String
    let createdAt: Date
    let expiresAt: Date?
    let requiresUserPresence: Bool
    let origin: String
    let privateKeyAvailable: Bool?

    var id: String { keyID }
    var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
    var canSign: Bool { (privateKeyAvailable ?? true) && !isExpired }

    var fingerprint: String {
        guard let data = Data(base64Encoded: publicKey) else { return "غير معروف" }
        return SHA256.hash(data: data)
            .prefix(8)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
}

enum SigningKeyLifetimePreset: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case thirtyDays
    case oneYear
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay: return "يوم واحد"
        case .sevenDays: return "7 أيام"
        case .thirtyDays: return "30 يومًا"
        case .oneYear: return "سنة واحدة"
        case .lifetime: return "مدى الحياة"
        }
    }

    func expirationDate(from start: Date = Date()) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        switch self {
        case .oneDay: return calendar.date(byAdding: .day, value: 1, to: start)
        case .sevenDays: return calendar.date(byAdding: .day, value: 7, to: start)
        case .thirtyDays: return calendar.date(byAdding: .day, value: 30, to: start)
        case .oneYear: return calendar.date(byAdding: .year, value: 1, to: start)
        case .lifetime: return nil
        }
    }
}

struct ThreeEPrivateKeyDocument: Codable {
    let schemaVersion: Int
    let algorithm: String
    let publisherID: String
    let publisherName: String
    let keyID: String
    let privateKey: String
    let publicKey: String?
}

enum LocalSigningKeyError: LocalizedError {
    case invalidPublisher
    case invalidKeyID
    case invalidKeyFile
    case unsupportedAlgorithm
    case duplicateKey
    case keyNotFound
    case keyExpired
    case keychain(OSStatus)
    case publicKeyMismatch

    var errorDescription: String? {
        switch self {
        case .invalidPublisher:
            return "بيانات الناشر غير صالحة."
        case .invalidKeyID:
            return "معرّف المفتاح غير صالح. استخدم حروفًا وأرقامًا ونقاطًا وشرطات فقط."
        case .invalidKeyFile:
            return "ملف المفتاح غير صالح أو لا يحتوي مفتاح Ed25519 مدعومًا."
        case .unsupportedAlgorithm:
            return "خوارزمية المفتاح غير مدعومة. الإصدار الحالي يدعم Ed25519."
        case .duplicateKey:
            return "يوجد مفتاح آخر بالمعرّف نفسه. احذفه أو استخدم معرّفًا مختلفًا."
        case .keyNotFound:
            return "لم يتم العثور على المفتاح الخاص في Keychain."
        case .keyExpired:
            return "انتهت صلاحية المفتاح ولا يمكن استخدامه لإنشاء توقيعات جديدة."
        case .keychain(let status):
            return "تعذر الوصول إلى Keychain. رمز الخطأ: \(status)"
        case .publicKeyMismatch:
            return "المفتاح العام لا يطابق المفتاح الخاص."
        }
    }
}

final class LocalSigningKeyStore: ObservableObject {
    static let shared = LocalSigningKeyStore()

    @Published private(set) var keys: [LocalSigningKeyMetadata] = []

    private let service = "com.essam.3E.localweb.signingkeys"
    private let registryKey = "3e.localweb.signingkeys.registry.v1"
    private let defaults = UserDefaults.standard

    private init() {
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: registryKey),
              let decoded = try? JSONDecoder().decode([LocalSigningKeyMetadata].self, from: data) else {
            keys = []
            return
        }
        keys = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func generateKey(
        publisherID: String,
        publisherName: String,
        keyID: String,
        lifetime: SigningKeyLifetimePreset,
        requiresUserPresence: Bool
    ) throws -> LocalSigningKeyMetadata {
        try validateIdentity(publisherID: publisherID, publisherName: publisherName, keyID: keyID)
        guard !keys.contains(where: { $0.keyID == keyID }) else { throw LocalSigningKeyError.duplicateKey }

        let privateKey = Curve25519.Signing.PrivateKey()
        let metadata = LocalSigningKeyMetadata(
            schemaVersion: 1,
            publisherID: publisherID,
            publisherName: publisherName,
            keyID: keyID,
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
            createdAt: Date(),
            expiresAt: lifetime.expirationDate(),
            requiresUserPresence: requiresUserPresence,
            origin: "generated-on-device",
            privateKeyAvailable: true
        )
        try savePrivateKey(privateKey.rawRepresentation, metadata: metadata)
        append(metadata)
        return metadata
    }

    @discardableResult
    func importKey(
        from url: URL,
        lifetime: SigningKeyLifetimePreset,
        requiresUserPresence: Bool
    ) throws -> LocalSigningKeyMetadata {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try importKey(
            data: data,
            filename: url.lastPathComponent,
            lifetime: lifetime,
            requiresUserPresence: requiresUserPresence
        )
    }

    @discardableResult
    func importKey(
        data: Data,
        filename: String,
        lifetime: SigningKeyLifetimePreset,
        requiresUserPresence: Bool
    ) throws -> LocalSigningKeyMetadata {
        let imported: (publisherID: String, publisherName: String, keyID: String, rawPrivateKey: Data, declaredPublicKey: Data?)

        if filename.lowercased().hasSuffix(".pem") || String(data: data, encoding: .utf8)?.contains("BEGIN PRIVATE KEY") == true {
            let raw = try Self.rawEd25519PrivateKey(fromPEMData: data)
            imported = (
                publisherID: "com.essam.3e",
                publisherName: "3E / Essam",
                keyID: "3e-imported-\(Self.timestampID())",
                rawPrivateKey: raw,
                declaredPublicKey: nil
            )
        } else {
            guard let document = try? JSONDecoder().decode(ThreeEPrivateKeyDocument.self, from: data),
                  document.schemaVersion == 1 else {
                throw LocalSigningKeyError.invalidKeyFile
            }
            guard document.algorithm.lowercased() == "ed25519" else {
                throw LocalSigningKeyError.unsupportedAlgorithm
            }
            guard let raw = Data(base64Encoded: document.privateKey) else {
                throw LocalSigningKeyError.invalidKeyFile
            }
            imported = (
                publisherID: document.publisherID,
                publisherName: document.publisherName,
                keyID: document.keyID,
                rawPrivateKey: raw,
                declaredPublicKey: document.publicKey.flatMap { Data(base64Encoded: $0) }
            )
        }

        try validateIdentity(
            publisherID: imported.publisherID,
            publisherName: imported.publisherName,
            keyID: imported.keyID
        )

        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: imported.rawPrivateKey)
        } catch {
            throw LocalSigningKeyError.invalidKeyFile
        }
        if let declared = imported.declaredPublicKey,
           declared != privateKey.publicKey.rawRepresentation {
            throw LocalSigningKeyError.publicKeyMismatch
        }

        let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
        if let existing = keys.first(where: { $0.keyID == imported.keyID }) {
            guard !(existing.privateKeyAvailable ?? true),
                  existing.publisherID == imported.publisherID,
                  existing.publicKey == publicKey else {
                throw LocalSigningKeyError.duplicateKey
            }
        }

        let metadata = LocalSigningKeyMetadata(
            schemaVersion: 1,
            publisherID: imported.publisherID,
            publisherName: imported.publisherName,
            keyID: imported.keyID,
            publicKey: publicKey,
            createdAt: Date(),
            expiresAt: lifetime.expirationDate(),
            requiresUserPresence: requiresUserPresence,
            origin: "imported",
            privateKeyAvailable: true
        )
        try savePrivateKey(privateKey.rawRepresentation, metadata: metadata)
        if let index = keys.firstIndex(where: { $0.keyID == metadata.keyID }) {
            keys[index] = metadata
            keys.sort { $0.createdAt > $1.createdAt }
            persist()
        } else {
            append(metadata)
        }
        return metadata
    }

    func privateKey(for metadata: LocalSigningKeyMetadata, reason: String) throws -> Curve25519.Signing.PrivateKey {
        guard metadata.canSign else {
            throw metadata.isExpired ? LocalSigningKeyError.keyExpired : LocalSigningKeyError.keyNotFound
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: metadata.keyID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if metadata.requiresUserPresence {
            query[kSecUseOperationPrompt as String] = reason
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw LocalSigningKeyError.keyNotFound }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LocalSigningKeyError.keychain(status)
        }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        } catch {
            throw LocalSigningKeyError.invalidKeyFile
        }
    }

    func delete(_ metadata: LocalSigningKeyMetadata) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: metadata.keyID
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LocalSigningKeyError.keychain(status)
        }
        if let index = keys.firstIndex(where: { $0.keyID == metadata.keyID }) {
            let current = keys[index]
            keys[index] = LocalSigningKeyMetadata(
                schemaVersion: current.schemaVersion,
                publisherID: current.publisherID,
                publisherName: current.publisherName,
                keyID: current.keyID,
                publicKey: current.publicKey,
                createdAt: current.createdAt,
                expiresAt: current.expiresAt,
                requiresUserPresence: current.requiresUserPresence,
                origin: current.origin,
                privateKeyAvailable: false
            )
        }
        persist()
    }

    func trustedPublisher(id: String, keyID: String) -> (TrustedPublisher, TrustedPublisherKey)? {
        guard let metadata = keys.first(where: { $0.publisherID == id && $0.keyID == keyID }) else {
            return nil
        }
        let key = TrustedPublisherKey(
            id: metadata.keyID,
            algorithm: "Ed25519",
            publicKey: metadata.publicKey
        )
        let publisher = TrustedPublisher(
            id: metadata.publisherID,
            name: metadata.publisherName,
            keys: [key]
        )
        return (publisher, key)
    }

    func exportPublicPublisherDocument(for metadata: LocalSigningKeyMetadata) throws -> Data {
        let list = TrustedPublisherList(
            schemaVersion: 1,
            publishers: [
                TrustedPublisher(
                    id: metadata.publisherID,
                    name: metadata.publisherName,
                    keys: [
                        TrustedPublisherKey(
                            id: metadata.keyID,
                            algorithm: "Ed25519",
                            publicKey: metadata.publicKey
                        )
                    ]
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(list)
    }

    private func savePrivateKey(_ data: Data, metadata: LocalSigningKeyMetadata) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: metadata.keyID,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false
        ]

        if metadata.requiresUserPresence {
            var accessError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.userPresence],
                &accessError
            ) else {
                if let error = accessError?.takeRetainedValue() { throw error }
                throw LocalSigningKeyError.invalidKeyFile
            }
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw LocalSigningKeyError.keychain(status) }
    }

    private func append(_ metadata: LocalSigningKeyMetadata) {
        keys.append(metadata)
        keys.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(keys) {
            defaults.set(data, forKey: registryKey)
        }
    }

    private func validateIdentity(publisherID: String, publisherName: String, keyID: String) throws {
        let publisherPattern = "^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$"
        guard publisherID.range(of: publisherPattern, options: .regularExpression) != nil,
              !publisherID.contains(".."),
              !publisherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalSigningKeyError.invalidPublisher
        }
        let keyPattern = "^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$"
        guard keyID.range(of: keyPattern, options: .regularExpression) != nil else {
            throw LocalSigningKeyError.invalidKeyID
        }
    }

    private static func rawEd25519PrivateKey(fromPEMData data: Data) throws -> Data {
        guard let pem = String(data: data, encoding: .utf8) else {
            throw LocalSigningKeyError.invalidKeyFile
        }
        let body = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: body), der.count >= 32 else {
            throw LocalSigningKeyError.invalidKeyFile
        }

        // PKCS#8 Ed25519 generated by OpenSSL/cryptography ends with the 32-byte seed.
        let expectedPrefix = Data([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20])
        guard der.count == 48, der.prefix(expectedPrefix.count) == expectedPrefix else {
            throw LocalSigningKeyError.invalidKeyFile
        }
        return der.suffix(32)
    }

    private static func timestampID() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
