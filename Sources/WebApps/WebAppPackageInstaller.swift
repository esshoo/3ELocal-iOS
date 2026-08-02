import Foundation
import ZIPFoundation

struct WebAppInstallOutcome {
    enum Kind {
        case installed
        case updated(from: String)
        case reinstalled
    }

    let app: InstalledWebApp
    let kind: Kind
}

enum WebAppPackageInstaller {
    static let recordFileName = "app-info.json"
    private static let maximumPackageBytes: Int64 = 250 * 1_024 * 1_024
    private static let maximumExpandedBytes: UInt64 = 750 * 1_024 * 1_024
    private static let maximumEntries = 20_000
    private static let blockedExtensions: Set<String> = [
        "app", "appex", "framework", "dylib", "so", "ipa", "apk", "aab",
        "dex", "jar", "class", "xpc", "kext", "mobileconfig", "pkg", "dmg"
    ]

    static func install(
        packageURL: URL,
        installedAppsRoot: URL,
        temporaryRoot: URL
    ) throws -> WebAppInstallOutcome {
        let didAccess = packageURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { packageURL.stopAccessingSecurityScopedResource() }
        }

        let ext = packageURL.pathExtension.lowercased()
        guard ext == "3eweb" || ext == "zip" else {
            throw WebAppPackageError.unsupportedFile
        }

        let values = try packageURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw WebAppPackageError.unsupportedFile }
        if Int64(values.fileSize ?? 0) > maximumPackageBytes {
            throw WebAppPackageError.packageTooLarge
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: installedAppsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let workURL = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extractionURL = workURL.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workURL) }

        let archive: Archive
        do {
            archive = try Archive(url: packageURL, accessMode: .read)
        } catch {
            throw WebAppPackageError.invalidArchive
        }

        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            if entryCount > maximumEntries { throw WebAppPackageError.tooManyEntries }

            expandedBytes += entry.uncompressedSize
            if expandedBytes > maximumExpandedBytes {
                throw WebAppPackageError.expandedSizeTooLarge
            }

            guard let safePath = safeArchivePath(entry.path) else {
                throw WebAppPackageError.unsafePath(entry.path)
            }

            if entry.type == .symlink {
                throw WebAppPackageError.symbolicLinksNotAllowed
            }

            let fileExtension = URL(fileURLWithPath: safePath).pathExtension.lowercased()
            if blockedExtensions.contains(fileExtension) {
                throw WebAppPackageError.nativeExecutableNotAllowed(entry.path)
            }
        }

        do {
            try fileManager.unzipItem(at: packageURL, to: extractionURL)
        } catch {
            throw WebAppPackageError.invalidArchive
        }

        let packageRoot = try locatePackageRoot(in: extractionURL)
        let manifestURL = packageRoot.appendingPathComponent("manifest.json")
        let manifest = try decodeManifest(at: manifestURL)
        try validate(manifest: manifest, packageRoot: packageRoot)

        let appContainer = installedAppsRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let versionsURL = appContainer.appendingPathComponent("Versions", isDirectory: true)
        let destinationVersionURL = versionsURL.appendingPathComponent(manifest.version, isDirectory: true)
        let recordURL = appContainer.appendingPathComponent(recordFileName)

        let existingRecord = try? loadRecord(at: recordURL)
        if let existingRecord, existingRecord.activeManifest.type != .local {
            throw WebAppPackageError.invalidManifest("المعرّف مستخدم بواسطة تطبيق من نوع مختلف.")
        }
        let outcomeKind: WebAppInstallOutcome.Kind
        if let existingRecord {
            if existingRecord.activeVersion == manifest.version {
                outcomeKind = .reinstalled
            } else {
                outcomeKind = .updated(from: existingRecord.activeVersion)
            }
        } else {
            outcomeKind = .installed
        }

        try fileManager.createDirectory(at: versionsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: appContainer.appendingPathComponent("Data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: appContainer.appendingPathComponent("Documents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: appContainer.appendingPathComponent("Cache", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: appContainer.appendingPathComponent("Backups", isDirectory: true),
            withIntermediateDirectories: true
        )

        let stagedVersionURL = versionsURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: packageRoot, to: stagedVersionURL)

        if fileManager.fileExists(atPath: destinationVersionURL.path) {
            try fileManager.removeItem(at: destinationVersionURL)
        }
        try fileManager.moveItem(at: stagedVersionURL, to: destinationVersionURL)

        let now = Date()
        let newRecord = InstalledWebAppRecord(
            schemaVersion: 1,
            activeManifest: manifest,
            activeVersion: manifest.version,
            previousVersion: existingRecord.flatMap {
                $0.activeVersion == manifest.version ? $0.previousVersion : $0.activeVersion
            },
            installedAt: existingRecord?.installedAt ?? now,
            updatedAt: now,
            lastLaunchedAt: existingRecord?.lastLaunchedAt,
            launchCount: existingRecord?.launchCount
        )
        try writeRecord(newRecord, to: recordURL)

        return WebAppInstallOutcome(
            app: InstalledWebApp(record: newRecord, containerURL: appContainer),
            kind: outcomeKind
        )
    }

    static func scanInstalledApps(in installedAppsRoot: URL) throws -> [InstalledWebApp] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: installedAppsRoot.path) else { return [] }

        let children = try fileManager.contentsOfDirectory(
            at: installedAppsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )

        var apps: [InstalledWebApp] = []
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard values.isDirectory == true, values.isHidden != true else { continue }

            let recordURL = child.appendingPathComponent(recordFileName)
            guard let record = try? loadRecord(at: recordURL),
                  record.activeManifest.id == child.lastPathComponent,
                  isSafeVersion(record.activeVersion) else { continue }
            let app = InstalledWebApp(record: record, containerURL: child)
            guard (try? validate(manifest: record.activeManifest, packageRoot: app.activePackageURL, allowRemote: true)) != nil else {
                continue
            }
            apps.append(app)
        }

        return apps.sorted {
            if $0.record.updatedAt != $1.record.updatedAt {
                return $0.record.updatedAt > $1.record.updatedAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func uninstall(_ app: InstalledWebApp) throws {
        try FileManager.default.removeItem(at: app.containerURL)
    }

    static func rollback(_ app: InstalledWebApp) throws -> InstalledWebApp {
        guard app.appType == .local else {
            throw WebAppPackageError.unsupportedAppType(app.appType.rawValue)
        }
        guard let previous = app.record.previousVersion, isSafeVersion(previous) else {
            throw WebAppPackageError.versionMissing("previous")
        }

        let previousURL = app.containerURL
            .appendingPathComponent("Versions", isDirectory: true)
            .appendingPathComponent(previous, isDirectory: true)
        guard FileManager.default.fileExists(atPath: previousURL.path) else {
            throw WebAppPackageError.versionMissing(previous)
        }

        let previousManifest = try decodeManifest(
            at: previousURL.appendingPathComponent("manifest.json")
        )
        var record = app.record
        let currentVersion = record.activeVersion
        record.activeManifest = previousManifest
        record.activeVersion = previous
        record.previousVersion = currentVersion
        record.updatedAt = Date()

        try writeRecord(record, to: app.containerURL.appendingPathComponent(recordFileName))
        return InstalledWebApp(record: record, containerURL: app.containerURL)
    }

    private static func safeArchivePath(_ path: String) -> String? {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\u{0000}"),
              !path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").contains(where: { $0 == ".." }) else {
            return nil
        }

        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return PathSafety.safeRelativePath(normalized) ?? (normalized.hasSuffix("/") ? String(normalized.dropLast()) : nil)
    }

    private static func locatePackageRoot(in extractionURL: URL) throws -> URL {
        let directManifest = extractionURL.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: directManifest.path) {
            return extractionURL
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: extractionURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )
        let directories = try children.filter {
            try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }

        if directories.count == 1 {
            let nestedManifest = directories[0].appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: nestedManifest.path) {
                return directories[0]
            }
        }

        throw WebAppPackageError.missingManifest
    }

    private static func decodeManifest(at url: URL) throws -> WebAppManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WebAppPackageError.missingManifest
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WebAppManifest.self, from: data)
        } catch let error as WebAppPackageError {
            throw error
        } catch {
            throw WebAppPackageError.invalidManifest(error.localizedDescription)
        }
    }

    static func validate(
        manifest: WebAppManifest,
        packageRoot: URL,
        allowRemote: Bool = false
    ) throws {
        guard manifest.schemaVersion == 1 else {
            throw WebAppPackageError.unsupportedSchema(manifest.schemaVersion)
        }
        if manifest.type == .remote && !allowRemote {
            throw WebAppPackageError.unsupportedAppType(manifest.type.rawValue)
        }
        guard manifest.type == .local || manifest.type == .remote else {
            throw WebAppPackageError.unsupportedAppType(manifest.type.rawValue)
        }

        let idPattern = "^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$"
        guard manifest.id.range(of: idPattern, options: .regularExpression) != nil,
              !manifest.id.contains("..") else {
            throw WebAppPackageError.invalidIdentifier
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 100 else {
            throw WebAppPackageError.invalidManifest("اسم التطبيق مفقود أو طويل جدًا.")
        }
        guard isSafeVersion(manifest.version) else {
            throw WebAppPackageError.invalidVersion
        }

        if let minimum = manifest.minimumRuntimeVersion,
           !WebAppVersion.isAtLeast(ThreeEAppIdentity.runtimeVersion, minimum: minimum) {
            throw WebAppPackageError.runtimeTooOld(
                required: minimum,
                current: ThreeEAppIdentity.runtimeVersion
            )
        }

        switch manifest.type {
        case .local:
            guard let entry = manifest.entry,
                  let safeEntry = PathSafety.safeRelativePath(entry),
                  ["html", "htm"].contains(URL(fileURLWithPath: safeEntry).pathExtension.lowercased()) else {
                throw WebAppPackageError.invalidEntry(manifest.entry ?? "")
            }
            let entryURL = packageRoot.appendingPathComponent(safeEntry)
            guard FileManager.default.fileExists(atPath: entryURL.path) else {
                throw WebAppPackageError.missingEntry(entry)
            }

        case .remote:
            guard let rawURL = manifest.startURL,
                  let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https",
                  url.host != nil else {
                throw WebAppPackageError.invalidRemoteURL(manifest.startURL ?? "")
            }
            try validateDomains(manifest.allowedDomains ?? [])

        case .hybrid:
            throw WebAppPackageError.unsupportedAppType(manifest.type.rawValue)
        }

        if let icon = manifest.icon {
            guard let safeIcon = PathSafety.safeRelativePath(icon) else {
                throw WebAppPackageError.invalidIcon(icon)
            }
            let iconURL = packageRoot.appendingPathComponent(safeIcon)
            guard FileManager.default.fileExists(atPath: iconURL.path) else {
                throw WebAppPackageError.invalidIcon(icon)
            }
        }
    }

    private static func validateDomains(_ domains: [String]) throws {
        guard domains.count <= 50 else {
            throw WebAppPackageError.invalidManifest("عدد النطاقات المسموح بها كبير جدًا.")
        }
        let pattern = "^[A-Za-z0-9.-]+$"
        for domain in domains {
            let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  normalized.count <= 253,
                  normalized.range(of: pattern, options: .regularExpression) != nil,
                  !normalized.contains("..") else {
                throw WebAppPackageError.invalidManifest("نطاق غير صالح: \(domain)")
            }
        }
    }


    static func isSafeVersion(_ version: String) -> Bool {
        let versionPattern = "^[A-Za-z0-9][A-Za-z0-9._+-]{0,49}$"
        return version.range(of: versionPattern, options: .regularExpression) != nil &&
            !version.contains("..")
    }

    static func loadRecord(at url: URL) throws -> InstalledWebAppRecord {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WebAppPackageError.recordMissing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InstalledWebAppRecord.self, from: Data(contentsOf: url))
    }

    static func writeRecord(_ record: InstalledWebAppRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: url, options: .atomic)
    }
}
