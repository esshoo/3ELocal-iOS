import SwiftUI

struct RootView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager

    var body: some View {
        Group {
            if storage.isConnected {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert("3ELocal", isPresented: Binding(
            get: { !storage.isConnected && storage.errorMessage != nil },
            set: { if !$0 { storage.errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) { storage.errorMessage = nil }
        } message: {
            Text(storage.errorMessage ?? "")
        }
    }
}
