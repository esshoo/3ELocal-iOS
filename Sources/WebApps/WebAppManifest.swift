import Foundation

struct WebAppManifest: Codable, Hashable {
    enum AppType: String, Codable, CaseIterable {
        case local
        case remote
        case hybrid
    }

    let schemaVersion: Int
    let id: String
    let name: String
    let version: String
    let description: String?
    let icon: String?
    let entry: String
    let type: AppType
    let minimumRuntimeVersion: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case version
        case description
        case icon
        case entry
        case type
        case minimumRuntimeVersion
    }
}

struct InstalledWebAppRecord: Codable, Hashable {
    let schemaVersion: Int
    var activeManifest: WebAppManifest
    var activeVersion: String
    var previousVersion: String?
    let installedAt: Date
    var updatedAt: Date
}

struct InstalledWebApp: Identifiable, Hashable {
    let record: InstalledWebAppRecord
    let containerURL: URL

    var id: String { record.activeManifest.id }
    var name: String { record.activeManifest.name }
    var version: String { record.activeVersion }
    var appDescription: String? { record.activeManifest.description }
    var appType: WebAppManifest.AppType { record.activeManifest.type }

    var activePackageURL: URL {
        containerURL
            .appendingPathComponent("Versions", isDirectory: true)
            .appendingPathComponent(record.activeVersion, isDirectory: true)
    }

    var entryURL: URL {
        activePackageURL.appendingPathComponent(record.activeManifest.entry)
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

    var previousVersion: String? { record.previousVersion }
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
