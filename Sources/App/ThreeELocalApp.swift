import SwiftUI

@main
struct ThreeELocalApp: App {
    @StateObject private var storage = ThreeEStorageManager()
    @StateObject private var library = ProjectLibraryStore()
    @StateObject private var router = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(storage)
                .environmentObject(library)
                .environmentObject(router)
                .onOpenURL { url in
                    if url.isFileURL && url.pathExtension.lowercased() == "3eweb" {
                        storage.handleIncomingWebAppPackage(from: url)
                    } else if url.scheme?.lowercased() == ThreeEAppIdentity.urlScheme,
                              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        switch url.host?.lowercased() {
                        case "install":
                            if let value = components.queryItems?.first(where: { $0.name == "url" })?.value {
                                storage.downloadPackage(from: value)
                            }
                        case "catalog":
                            if let value = components.queryItems?.first(where: { $0.name == "url" })?.value {
                                storage.catalogURLString = value
                                Task { await storage.fetchCatalog() }
                            }
                        default:
                            router.handle(url)
                        }
                    } else {
                        router.handle(url)
                    }
                }
        }
    }
}
