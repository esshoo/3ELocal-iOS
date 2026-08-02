import Foundation
import UIKit

struct RemoteWebAppDraft {
    let name: String
    let startURL: URL
    let appDescription: String?
    let iconData: Data?
    let navigationPolicy: WebAppManifest.NavigationPolicy
    let allowedDomains: [String]
}

enum RemoteWebAppInstaller {
    private static let remoteVersion = "1.0.0"
    private static let maximumIconBytes = 8 * 1_024 * 1_024

    static func install(
        draft: RemoteWebAppDraft,
        installedAppsRoot: URL
    ) throws -> WebAppInstallOutcome {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else {
            throw WebAppPackageError.invalidManifest("اسم التطبيق مفقود أو طويل جدًا.")
        }

        let url = draft.startURL
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw WebAppPackageError.invalidRemoteURL(url.absoluteString)
        }

        let identifier = identifier(for: url)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: installedAppsRoot, withIntermediateDirectories: true)

        let appContainer = installedAppsRoot.appendingPathComponent(identifier, isDirectory: true)
        let versionsURL = appContainer.appendingPathComponent("Versions", isDirectory: true)
        let versionURL = versionsURL.appendingPathComponent(remoteVersion, isDirectory: true)
        let recordURL = appContainer.appendingPathComponent(WebAppPackageInstaller.recordFileName)
        let existingRecord = try? WebAppPackageInstaller.loadRecord(at: recordURL)
        if let existingRecord, existingRecord.activeManifest.type != .remote {
            throw WebAppPackageError.invalidManifest("المعرّف مستخدم بواسطة تطبيق من نوع مختلف.")
        }

        try fileManager.createDirectory(at: appContainer, withIntermediateDirectories: true)
        for folder in ["Data", "Documents", "Cache", "Backups"] {
            try fileManager.createDirectory(
                at: appContainer.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let stagingURL = versionsURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        var iconRelativePath: String?
        if let iconData = draft.iconData,
           !iconData.isEmpty,
           iconData.count <= maximumIconBytes,
           let image = UIImage(data: iconData),
           let png = image.pngData() {
            let iconName = "icon.png"
            try png.write(to: stagingURL.appendingPathComponent(iconName), options: .atomic)
            iconRelativePath = iconName
        }

        var domains = Set(draft.allowedDomains.map(normalizeDomain).filter { !$0.isEmpty })
        if let host = url.host?.lowercased() { domains.insert(host) }

        let manifest = WebAppManifest(
            schemaVersion: 1,
            id: identifier,
            name: name,
            version: remoteVersion,
            description: normalizedOptional(draft.appDescription),
            icon: iconRelativePath,
            entry: nil,
            startURL: url.absoluteString,
            type: .remote,
            minimumRuntimeVersion: ThreeEAppIdentity.runtimeVersion,
            updateURL: nil,
            navigationPolicy: draft.navigationPolicy,
            allowedDomains: domains.sorted()
        )

        try WebAppPackageInstaller.validate(
            manifest: manifest,
            packageRoot: stagingURL,
            allowRemote: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: stagingURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        try fileManager.createDirectory(at: versionsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: versionURL.path) {
            try fileManager.removeItem(at: versionURL)
        }
        try fileManager.moveItem(at: stagingURL, to: versionURL)

        let now = Date()
        let record = InstalledWebAppRecord(
            schemaVersion: 1,
            activeManifest: manifest,
            activeVersion: remoteVersion,
            previousVersion: nil,
            installedAt: existingRecord?.installedAt ?? now,
            updatedAt: now,
            lastLaunchedAt: existingRecord?.lastLaunchedAt,
            launchCount: existingRecord?.launchCount,
            packageTrust: .remote
        )
        try WebAppPackageInstaller.writeRecord(record, to: recordURL)

        return WebAppInstallOutcome(
            app: InstalledWebApp(record: record, containerURL: appContainer),
            kind: existingRecord == nil ? .installed : .reinstalled
        )
    }

    static func markLaunched(_ app: InstalledWebApp) throws -> InstalledWebApp {
        var record = app.record
        record.lastLaunchedAt = Date()
        record.launchCount = (record.launchCount ?? 0) + 1
        try WebAppPackageInstaller.writeRecord(record, to: app.recordURL)
        return InstalledWebApp(record: record, containerURL: app.containerURL)
    }

    private static func identifier(for url: URL) -> String {
        let host = (url.host ?? "website")
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "." || character == "-" {
                    return character
                }
                return "-"
            }
        let cleanHost = String(host).prefix(70)
        return "remote.\(cleanHost).\(stableHash(url.absoluteString))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func normalizeDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: trimmed), let host = url.host {
            return host.lowercased()
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
