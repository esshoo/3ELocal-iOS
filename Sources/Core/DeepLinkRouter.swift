import Foundation
import Combine

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingRelativePath: String?
    @Published var lastError: String?

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == ThreeEAppIdentity.urlScheme else { return }
        guard url.host?.lowercased() == "open" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              let safePath = PathSafety.safeRelativePath(path) else {
            lastError = "The incoming 3E path is invalid."
            return
        }

        pendingRelativePath = safePath
    }

    func clear() {
        pendingRelativePath = nil
    }

}
