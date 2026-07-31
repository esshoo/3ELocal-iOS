import Foundation

enum ThreeEStorageError: LocalizedError {
    case folderNotConnected
    case invalidFolder
    case accessDenied
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .folderNotConnected: return "3E folder is not connected."
        case .invalidFolder: return "The selected folder cannot be used."
        case .accessDenied: return "3ELocal could not access the selected folder."
        case .projectNotFound: return "The requested web project was not found."
        }
    }
}
