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
                        storage.installWebAppPackage(from: url)
                    } else {
                        router.handle(url)
                    }
                }
        }
    }
}
