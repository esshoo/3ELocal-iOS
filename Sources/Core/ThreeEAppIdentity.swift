import Foundation

enum ThreeEAppIdentity {
    static let appKey = "localWeb"
    static let bundleIdentifier = "com.essam.3E.localweb"
    static let displayName = "3ELocal"
    static let folderName = "LocalWeb"
    static let relativeFolderPath = "Apps/LocalWeb"
    static let urlScheme = "localweb"
    static let futureAppGroupIdentifier = "group.com.essam.3e"
    static let schemaVersion = 1
    static let runtimeVersion = "0.2.0"
}

enum ThreeEApp: String, CaseIterable, Codable {
    case lidar
    case roomElectrical
    case localWeb

    var displayName: String {
        switch self {
        case .lidar: return "3ELiDAR"
        case .roomElectrical: return "3ERoomElectrical"
        case .localWeb: return "3ELocal"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .lidar: return "com.essam.3E.LiDARLab"
        case .roomElectrical: return "com.essam.3E.roomelectrical"
        case .localWeb: return "com.essam.3E.localweb"
        }
    }

    var urlScheme: String {
        switch self {
        case .lidar: return "lidar"
        case .roomElectrical: return "electrical"
        case .localWeb: return "localweb"
        }
    }

    var folderPath: String {
        switch self {
        case .lidar: return "Apps/LiDARLab"
        case .roomElectrical: return "Apps/RoomElectrical"
        case .localWeb: return "Apps/LocalWeb"
        }
    }

    func makeURL(command: String = "open", relativePath: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = command
        if let relativePath {
            components.queryItems = [URLQueryItem(name: "path", value: relativePath)]
        }
        return components.url
    }
}
