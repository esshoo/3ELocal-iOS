import Foundation

struct WebAppManifest: Codable, Hashable {
    enum AppType: String, Codable, CaseIterable {
        case local
        case remote
        case hybrid
    }

    enum NavigationPolicy: String, Codable, CaseIterable {
        /// Keep main-frame navigation on the start host and its declared allowed domains.
        case allowedDomains
        /// Permit navigation to any HTTP or HTTPS destination inside 3ELocal.
        case unrestricted
        /// Keep the app on its start host and send external links to the system browser.
        case sameHost
    }

    let schemaVersion: Int
    let id: String
    let name: String
    let version: String
    let description: String?
    let icon: String?
    let entry: String?
    let startURL: String?
    let type: AppType
    let minimumRuntimeVersion: String?
    let navigationPolicy: NavigationPolicy?
    let allowedDomains: [String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case version
        case description
        case icon
        case entry
        case startURL
        case type
        case minimumRuntimeVersion
        case navigationPolicy
        case allowedDomains
    }
}

struct InstalledWebAppRecord: Codable, Hashable {
    let schemaVersion: Int
    var activeManifest: WebAppManifest
    var activeVersion: String
    var previousVersion: String?
    let installedAt: Date
    var updatedAt: Date
    var lastLaunchedAt: Date?
    var launchCount: Int?
}

struct InstalledWebApp: Identifiable, Hashable {
    let record: InstalledWebAppRecord
    let containerURL: URL

    var id: String { record.activeManifest.id }
    var name: String { record.activeManifest.name }
    var version: String { record.activeVersion }
    var appDescription: String? { record.activeManifest.description }
    var appType: WebAppManifest.AppType { record.activeManifest.type }
    var navigationPolicy: WebAppManifest.NavigationPolicy {
        record.activeManifest.navigationPolicy ?? (isRemote ? .sameHost : .unrestricted)
    }
    var allowedDomains: [String] { record.activeManifest.allowedDomains ?? [] }
    var isRemote: Bool { appType == .remote }
    var isLocal: Bool { appType == .local }

    var activePackageURL: URL {
        containerURL
            .appendingPathComponent("Versions", isDirectory: true)
            .appendingPathComponent(record.activeVersion, isDirectory: true)
    }

    var entryURL: URL? {
        guard let entry = record.activeManifest.entry,
              let safeEntry = PathSafety.safeRelativePath(entry) else {
            return nil
        }
        return activePackageURL.appendingPathComponent(safeEntry)
    }

    var remoteURL: URL? {
        guard let raw = record.activeManifest.startURL,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    var iconURL: URL? {
        guard let relativeIcon = record.activeManifest.icon,
              let safeIcon = PathSafety.safeRelativePath(relativeIcon) else {
            return nil
        }
        return activePackageURL.appendingPathComponent(safeIcon)
    }

    var dataURL: URL {
        containerURL.appendingPathComponent("Data", isDirectory: true)
    }

    var documentsURL: URL {
        containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    var recordURL: URL {
        containerURL.appendingPathComponent(WebAppPackageInstaller.recordFileName)
    }

    var previousVersion: String? { record.previousVersion }
    var installedAt: Date { record.installedAt }
    var updatedAt: Date { record.updatedAt }
    var lastLaunchedAt: Date? { record.lastLaunchedAt }
    var launchCount: Int { record.launchCount ?? 0 }

    var storageSizeBytes: Int64 {
        FileSystemSize.directorySize(at: containerURL)
    }

    var typeDisplayName: String {
        switch appType {
        case .local: return "محلي"
        case .remote: return "إنترنت"
        case .hybrid: return "هجين"
        }
    }

    var primaryHost: String? {
        remoteURL?.host?.lowercased()
    }

    var effectiveAllowedHosts: Set<String> {
        var hosts = Set(allowedDomains.compactMap(Self.normalizedHost))
        if let primaryHost { hosts.insert(primaryHost) }
        return hosts
    }

    private static func normalizedHost(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host {
            return host.lowercased()
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

enum WebAppVersion {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        return lhs.localizedStandardCompare(rhs)
    }

    static func isAtLeast(_ version: String, minimum: String) -> Bool {
        compare(version, minimum) != .orderedAscending
    }

    private static func components(_ value: String) -> [Int] {
        value
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}

enum FileSystemSize {
    static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
