import Foundation

struct WebAppCatalog: Codable, Hashable {
    let schemaVersion: Int
    let name: String?
    let updatedAt: String?
    let apps: [WebAppCatalogEntry]
}

struct WebAppCatalogEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let iconURL: String?
    let packageURL: String
    let minimumRuntimeVersion: String?

    func resolvedPackageURL(relativeTo catalogURL: URL) -> URL? {
        Self.resolve(packageURL, relativeTo: catalogURL)
    }

    func resolvedIconURL(relativeTo catalogURL: URL) -> URL? {
        guard let iconURL else { return nil }
        return Self.resolve(iconURL, relativeTo: catalogURL)
    }

    var isRuntimeCompatible: Bool {
        guard let minimumRuntimeVersion else { return true }
        return WebAppVersion.isAtLeast(
            ThreeEAppIdentity.runtimeVersion,
            minimum: minimumRuntimeVersion
        )
    }

    private static func resolve(_ value: String, relativeTo baseURL: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }
}

enum WebAppCatalogError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedSchema(Int)
    case tooManyApps
    case invalidEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "رابط فهرس التطبيقات غير صالح. يجب استخدام HTTPS."
        case .invalidResponse:
            return "تعذر قراءة فهرس التطبيقات من الخادم."
        case .unsupportedSchema(let version):
            return "إصدار صيغة الفهرس غير مدعوم: \(version)."
        case .tooManyApps:
            return "يحتوي الفهرس على عدد تطبيقات أكبر من الحد المسموح."
        case .invalidEntry(let name):
            return "بيانات التطبيق غير صالحة داخل الفهرس: \(name)."
        }
    }
}
