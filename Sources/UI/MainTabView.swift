import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            InstalledWebAppsView()
                .tabItem {
                    Label("التطبيقات", systemImage: "square.grid.2x2")
                }

            ProjectLibraryView()
                .tabItem {
                    Label("المشاريع", systemImage: "folder")
                }
        }
    }
}
