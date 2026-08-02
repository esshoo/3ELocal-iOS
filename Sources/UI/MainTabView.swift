import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager

    var body: some View {
        TabView {
            InstalledWebAppsView()
                .tabItem {
                    Label("التطبيقات", systemImage: "square.grid.2x2")
                }

            WebAppCatalogView()
                .tabItem {
                    Label("المتجر", systemImage: "square.grid.3x3.fill")
                }
                .badge(storage.availableUpdateCount)

            WebAppDownloadsView(downloads: storage.downloadManager)
                .tabItem {
                    Label("التنزيلات", systemImage: "arrow.down.circle")
                }
                .badge(storage.downloadManager.items.filter {
                    $0.state == .downloaded || $0.state == .failed
                }.count)

            ProjectLibraryView()
                .tabItem {
                    Label("المشاريع", systemImage: "folder")
                }
        }
    }
}
