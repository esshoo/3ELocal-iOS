import Foundation

struct WebProject: Identifiable, Hashable {
    let id: String
    let name: String
    let relativePath: String
    let directoryURL: URL
    let indexURL: URL
    let modifiedAt: Date
    let fileCount: Int
    let totalBytes: Int64

    var subtitle: String {
        if totalBytes < 1_024 {
            return "\(fileCount) files · \(totalBytes) B"
        }
        if totalBytes < 1_048_576 {
            return "\(fileCount) files · \(totalBytes / 1_024) KB"
        }
        return "\(fileCount) files · \(totalBytes / 1_048_576) MB"
    }
}
