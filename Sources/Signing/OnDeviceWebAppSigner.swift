import Foundation
import CryptoKit
import ZIPFoundation

struct WebAppSigningResult: Hashable {
    let outputURL: URL
    let key: LocalSigningKeyMetadata
    let signedAt: Date
    let packageExpiresAt: Date?
}

enum PackageValidityPreset: String, CaseIterable, Identifiable {
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
        case .lifetime: return "بدون انتهاء"
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

struct SignedWebAppChecksums: Codable {
    let schemaVersion: Int
    let appID: String
    let version: String
    let signedAt: String
    let keyValidUntil: String?
    let packageValidUntil: String?
    let files: [WebAppChecksumEntry]
}

enum OnDeviceWebAppSigner {
    static func signInstalledApp(
        _ app: InstalledWebApp,
        key metadata: LocalSigningKeyMetadata,
        packageValidity: PackageValidityPreset,
        outputDirectory: URL
    ) throws -> WebAppSigningResult {
        guard app.isLocal else {
            throw WebAppPackageError.unsupportedAppType(app.appType.rawValue)
        }
        let privateKey = try LocalSigningKeyStore.shared.privateKey(
            for: metadata,
            reason: "استخدم Face ID أو رمز الجهاز لتوقيع \(app.name)"
        )

        let now = Date()
        let packageExpiresAt = packageValidity.expirationDate(from: now)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("3E-OnDeviceSigner", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packageRoot = workRoot.appendingPathComponent("Package", isDirectory: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workRoot) }

        try fileManager.copyItem(at: app.activePackageURL, to: packageRoot)
        for filename in [WebAppPackageVerifier.signatureFileName, WebAppPackageVerifier.defaultChecksumsFileName] {
            let candidate = packageRoot.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: candidate.path) {
                try fileManager.removeItem(at: candidate)
            }
        }

        let files = try regularFiles(in: packageRoot).map { fileURL -> WebAppChecksumEntry in
            let relative = String(fileURL.standardizedFileURL.path.dropFirst(packageRoot.standardizedFileURL.path.count + 1))
            return WebAppChecksumEntry(path: relative, sha256: try sha256Hex(of: fileURL))
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let checksums = SignedWebAppChecksums(
            schemaVersion: 2,
            appID: app.id,
            version: app.version,
            signedAt: formatter.string(from: now),
            keyValidUntil: metadata.expiresAt.map { formatter.string(from: $0) },
            packageValidUntil: packageExpiresAt.map { formatter.string(from: $0) },
            files: files
        )
        let checksumsData = try canonicalJSON(checksums)
        try checksumsData.write(
            to: packageRoot.appendingPathComponent(WebAppPackageVerifier.defaultChecksumsFileName),
            options: .atomic
        )

        let signature = try privateKey.signature(for: checksumsData)
        let signatureDocument = WebAppPackageSignature(
            schemaVersion: 1,
            algorithm: "Ed25519",
            publisherID: metadata.publisherID,
            publisherName: metadata.publisherName,
            keyID: metadata.keyID,
            signedAt: formatter.string(from: now),
            checksumsFile: WebAppPackageVerifier.defaultChecksumsFileName,
            signature: signature.base64EncodedString()
        )
        let signatureEncoder = JSONEncoder()
        signatureEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let signatureData = try signatureEncoder.encode(signatureDocument)
        try signatureData.write(
            to: packageRoot.appendingPathComponent(WebAppPackageVerifier.signatureFileName),
            options: .atomic
        )

        let safeName = sanitizedFilename(app.name)
        let outputURL = uniqueOutputURL(
            in: outputDirectory,
            baseName: "\(safeName)-v\(app.version)-Signed",
            extension: "3eweb"
        )
        try fileManager.zipItem(at: packageRoot, to: outputURL, shouldKeepParent: false)

        return WebAppSigningResult(
            outputURL: outputURL,
            key: metadata,
            signedAt: now,
            packageExpiresAt: packageExpiresAt
        )
    }

    private static func regularFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw WebAppPackageError.symbolicLinksNotAllowed
            }
            guard values.isRegularFile == true else { continue }
            let relative = String(fileURL.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            guard let safe = PathSafety.safeRelativePath(relative), safe == relative else {
                throw WebAppPackageError.unsafePath(relative)
            }
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
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

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let result = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "3EWebApp" : result
    }

    private static func uniqueOutputURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }
}
