import Foundation
import CryptoKit

enum WebAppTrustState: String, Codable, Hashable {
    case trusted
    case unsigned
    case remote
}

struct WebAppPackageTrust: Codable, Hashable {
    let state: WebAppTrustState
    let publisherID: String?
    let publisherName: String?
    let keyID: String?
    let verifiedAt: Date?

    static let unsigned = WebAppPackageTrust(
        state: .unsigned,
        publisherID: nil,
        publisherName: nil,
        keyID: nil,
        verifiedAt: nil
    )

    static let remote = WebAppPackageTrust(
        state: .remote,
        publisherID: nil,
        publisherName: nil,
        keyID: nil,
        verifiedAt: nil
    )
}

struct TrustedPublisherList: Codable {
    let schemaVersion: Int
    let publishers: [TrustedPublisher]
}

struct TrustedPublisher: Codable, Hashable {
    let id: String
    let name: String
    let keys: [TrustedPublisherKey]
}

struct TrustedPublisherKey: Codable, Hashable {
    let id: String
    let algorithm: String
    let publicKey: String
}

struct WebAppPackageSignature: Codable {
    let schemaVersion: Int
    let algorithm: String
    let publisherID: String
    let publisherName: String
    let keyID: String
    let signedAt: String?
    let checksumsFile: String
    let signature: String
}

struct WebAppChecksums: Codable {
    let schemaVersion: Int
    let appID: String
    let version: String
    let files: [WebAppChecksumEntry]
}

struct WebAppChecksumEntry: Codable, Hashable {
    let path: String
    let sha256: String
}

enum TrustedPublisherStore {
    private static let list: TrustedPublisherList = {
        guard let url = Bundle.main.url(forResource: "TrustedPublishers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TrustedPublisherList.self, from: data),
              decoded.schemaVersion == 1 else {
            return TrustedPublisherList(schemaVersion: 1, publishers: [])
        }
        return decoded
    }()

    static func publisher(id: String, keyID: String) -> (TrustedPublisher, TrustedPublisherKey)? {
        guard let publisher = list.publishers.first(where: { $0.id == id }),
              let key = publisher.keys.first(where: { $0.id == keyID }) else {
            return nil
        }
        return (publisher, key)
    }
}

enum WebAppPackageVerifier {
    static let signatureFileName = "signature.json"
    static let defaultChecksumsFileName = "checksums.json"

    static func verify(
        packageRoot: URL,
        manifest: WebAppManifest,
        allowUnsigned: Bool
    ) throws -> WebAppPackageTrust {
        let fileManager = FileManager.default
        let signatureURL = packageRoot.appendingPathComponent(signatureFileName)
        let defaultChecksumsURL = packageRoot.appendingPathComponent(defaultChecksumsFileName)
        let hasSignature = fileManager.fileExists(atPath: signatureURL.path)
        let hasChecksums = fileManager.fileExists(atPath: defaultChecksumsURL.path)

        if !hasSignature && !hasChecksums {
            guard allowUnsigned else { throw WebAppPackageError.signatureRequired }
            return .unsigned
        }
        guard hasSignature else { throw WebAppPackageError.signatureIncomplete }

        let signatureDocument: WebAppPackageSignature
        do {
            signatureDocument = try JSONDecoder().decode(
                WebAppPackageSignature.self,
                from: Data(contentsOf: signatureURL)
            )
        } catch {
            throw WebAppPackageError.invalidSignatureDocument
        }

        guard signatureDocument.schemaVersion == 1,
              signatureDocument.algorithm.lowercased() == "ed25519" else {
            throw WebAppPackageError.unsupportedSignatureAlgorithm(signatureDocument.algorithm)
        }
        guard signatureDocument.checksumsFile == defaultChecksumsFileName else {
            throw WebAppPackageError.invalidSignatureDocument
        }

        let checksumsURL = packageRoot.appendingPathComponent(signatureDocument.checksumsFile)
        guard fileManager.fileExists(atPath: checksumsURL.path) else {
            throw WebAppPackageError.signatureIncomplete
        }

        guard let (publisher, key) = TrustedPublisherStore.publisher(
            id: signatureDocument.publisherID,
            keyID: signatureDocument.keyID
        ) else {
            throw WebAppPackageError.untrustedPublisher(signatureDocument.publisherName)
        }
        guard key.algorithm.lowercased() == "ed25519",
              let publicKeyData = Data(base64Encoded: key.publicKey),
              let signatureData = Data(base64Encoded: signatureDocument.signature) else {
            throw WebAppPackageError.invalidSignatureDocument
        }

        let checksumsData = try Data(contentsOf: checksumsURL)
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw WebAppPackageError.invalidSignatureDocument
        }
        guard publicKey.isValidSignature(signatureData, for: checksumsData) else {
            throw WebAppPackageError.invalidPackageSignature
        }

        let checksums: WebAppChecksums
        do {
            checksums = try JSONDecoder().decode(WebAppChecksums.self, from: checksumsData)
        } catch {
            throw WebAppPackageError.invalidChecksumsDocument
        }
        guard checksums.schemaVersion == 1,
              checksums.appID == manifest.id,
              checksums.version == manifest.version else {
            throw WebAppPackageError.signatureManifestMismatch
        }

        try validateChecksums(checksums, packageRoot: packageRoot)

        return WebAppPackageTrust(
            state: .trusted,
            publisherID: publisher.id,
            publisherName: publisher.name,
            keyID: key.id,
            verifiedAt: Date()
        )
    }

    static func verifyInstalledPackage(
        packageRoot: URL,
        manifest: WebAppManifest,
        expectedTrust: WebAppPackageTrust?
    ) throws -> WebAppPackageTrust {
        let actual = try verify(packageRoot: packageRoot, manifest: manifest, allowUnsigned: true)
        if expectedTrust?.state == .trusted {
            guard actual.state == .trusted,
                  actual.publisherID == expectedTrust?.publisherID,
                  actual.keyID == expectedTrust?.keyID else {
                throw WebAppPackageError.signatureDowngradeNotAllowed
            }
        }
        return actual
    }

    private static func validateChecksums(_ checksums: WebAppChecksums, packageRoot: URL) throws {
        var declaredPaths = Set<String>()
        for item in checksums.files {
            guard let safePath = PathSafety.safeRelativePath(item.path),
                  safePath == item.path,
                  ![signatureFileName, defaultChecksumsFileName].contains(safePath),
                  declaredPaths.insert(safePath).inserted else {
                throw WebAppPackageError.invalidChecksumsDocument
            }
            let fileURL = packageRoot.appendingPathComponent(safePath)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw WebAppPackageError.checksumFileMissing(safePath)
            }
            let actual = try sha256Hex(of: fileURL)
            guard actual.caseInsensitiveCompare(item.sha256) == .orderedSame else {
                throw WebAppPackageError.checksumMismatch(safePath)
            }
        }

        let actualPaths = try regularFilePaths(in: packageRoot)
            .filter { ![signatureFileName, defaultChecksumsFileName].contains($0) }
        guard Set(actualPaths) == declaredPaths else {
            let extra = Set(actualPaths).subtracting(declaredPaths).sorted().first
            throw WebAppPackageError.unsignedExtraFile(extra ?? "unknown")
        }
    }

    private static func regularFilePaths(in root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw WebAppPackageError.symbolicLinksNotAllowed }
            guard values.isRegularFile == true else { continue }
            let rootPath = root.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else {
                throw WebAppPackageError.unsafePath(filePath)
            }
            paths.append(String(filePath.dropFirst(rootPath.count + 1)))
        }
        return paths.sorted()
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
