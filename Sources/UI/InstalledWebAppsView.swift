import SwiftUI
import UniformTypeIdentifiers

struct InstalledWebAppsView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager

    @State private var searchText = ""
    @State private var previewApp: InstalledWebApp?
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var appPendingDeletion: InstalledWebApp?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 300), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if storage.installedWebApps.isEmpty {
                    EmptyInstalledAppsView {
                        showingImporter = true
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredApps) { app in
                                InstalledWebAppCardView(
                                    app: app,
                                    open: { previewApp = app },
                                    rollback: { storage.rollbackWebApp(app) },
                                    uninstall: { appPendingDeletion = app }
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("تطبيقات 3E Web")
            .searchable(text: $searchText, prompt: "ابحث عن تطبيق")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        storage.refreshInstalledWebApps()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("تثبيت حزمة .3eweb", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("الإعدادات", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .overlay {
                if storage.isInstallingWebApp {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        ProgressView("فحص الحزمة وتثبيتها…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .fullScreenCover(item: $previewApp) { app in
                InstalledWebAppPreviewView(app: app)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(storage)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.threeEWebPackage, .zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let packageURL = urls.first else { return }
                    storage.installWebAppPackage(from: packageURL)
                case .failure(let error):
                    storage.errorMessage = "تعذر اختيار الحزمة: \(error.localizedDescription)"
                }
            }
            .confirmationDialog(
                "حذف التطبيق؟",
                isPresented: Binding(
                    get: { appPendingDeletion != nil },
                    set: { if !$0 { appPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let app = appPendingDeletion {
                    Button("حذف \(app.name) وبياناته", role: .destructive) {
                        storage.uninstallWebApp(app)
                        appPendingDeletion = nil
                    }
                }
                Button("إلغاء", role: .cancel) {
                    appPendingDeletion = nil
                }
            } message: {
                Text("سيتم حذف جميع إصدارات التطبيق ومجلدات Data وDocuments الخاصة به.")
            }
            .alert("3ELocal", isPresented: messageBinding) {
                Button("حسنًا", role: .cancel) {
                    storage.operationMessage = nil
                    storage.errorMessage = nil
                }
            } message: {
                Text(storage.errorMessage ?? storage.operationMessage ?? "")
            }
        }
    }

    private var filteredApps: [InstalledWebApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return storage.installedWebApps }
        return storage.installedWebApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query) ||
            $0.version.localizedCaseInsensitiveContains(query)
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { storage.errorMessage != nil || storage.operationMessage != nil },
            set: { presented in
                if !presented {
                    storage.errorMessage = nil
                    storage.operationMessage = nil
                }
            }
        )
    }
}

private struct EmptyInstalledAppsView: View {
    let importPackage: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("لا توجد تطبيقات مثبتة")
                .font(.title2.bold())
            Text("ثبّت أول تطبيق HTML5 وJavaScript من حزمة بصيغة .3eweb. ستظل المشاريع المحلية الحالية موجودة في تبويب المشاريع.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button("تثبيت حزمة .3eweb", action: importPackage)
                .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
