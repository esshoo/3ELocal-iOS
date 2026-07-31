import Foundation

enum ThreeEStorageError: LocalizedError {
    case folderNotConnected
    case invalidFolder
    case accessDenied
    case projectNotFound
    case invalidRegistryRoot
    case invalidRegistryApps

    var errorDescription: String? {
        switch self {
        case .folderNotConnected:
            return "3E folder is not connected."
        case .invalidFolder:
            return "The selected folder cannot be used."
        case .accessDenied:
            return "3ELocal could not access the selected folder."
        case .projectNotFound:
            return "The requested web project was not found."
        case .invalidRegistryRoot:
            return "registry.json does not contain a valid JSON object and was not modified."
        case .invalidRegistryApps:
            return "The apps field in registry.json is neither a valid list nor a valid object, so it was not modified."
        }
    }
}
