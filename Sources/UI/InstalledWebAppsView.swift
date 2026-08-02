import SwiftUI
import UniformTypeIdentifiers

struct InstalledWebAppsView: View {
    private enum AppFilter: String, CaseIterable, Identifiable {
        case all
        case local
        case remote

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "الكل"
            case .local: return "محلي"
            case .remote: return "إنترنت"
            }
        }
    }

    @EnvironmentObject private var storage: ThreeEStorageManager
    @StateObject private var network = NetworkStatusMonitor()

    @State private var searchText = ""
    @State private var selectedFilter: AppFilter = .all
    @State private var previewApp: InstalledWebApp?
    @State private var detailsApp: InstalledWebApp?
    @State private var showingImporter = false
    @State private var showingRemoteEditor = false
    @State private var showingSettings = false
    @State private var appPendingDeletion: InstalledWebApp?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 300), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if storage.installedWebApps.isEmpty {
                    EmptyInstalledAppsView(
                        importPackage: { showingImporter = true },
                        addRemote: { showingRemoteEditor = true }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Picker("نوع التطبيقات", selection: $selectedFilter) {
                                ForEach(AppFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            if filteredApps.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 42))
                                        .foregroundStyle(.secondary)
                                    Text("لا توجد نتائج")
                                        .font(.title3.bold())
                                    Text("جرّب تغيير البحث أو نوع التطبيقات.")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 50)
                            } else {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(filteredApps) { app in
                                        InstalledWebAppCardView(
                                            app: app,
                                            isOnline: network.isOnline,
                                            open: { open(app) },
                                            details: { detailsApp = currentApp(withID: app.id) ?? app },
                                            rollback: { storage.rollbackWebApp(app) },
                                            uninstall: { appPendingDeletion = app }
                                        )
                                    }
                                }
                            }
                        }
                        .padding()
                    }
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
                            Label("تثبيت حزمة .3eweb", systemImage: "shippingbox.and.arrow.backward")
                        }
                        Button {
                            showingRemoteEditor = true
                        } label: {
                            Label("إضافة تطبيق من الإنترنت", systemImage: "globe.badge.chevron.backward")
                        }
                        Divider()
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
                        ProgressView("فحص التطبيق وحفظه…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .fullScreenCover(item: $previewApp) { app in
                InstalledWebAppPreviewView(app: app)
            }
            .sheet(item: $detailsApp) { app in
                InstalledWebAppDetailsView(
                    app: currentApp(withID: app.id) ?? app,
                    isOnline: network.isOnline,
                    open: { open(currentApp(withID: app.id) ?? app) },
                    rollback: {
                        detailsApp = nil
                        storage.rollbackWebApp(app)
                    },
                    uninstall: {
                        detailsApp = nil
                        appPendingDeletion = app
                    }
                )
            }
            .sheet(isPresented: $showingRemoteEditor) {
                RemoteWebAppEditorView { draft in
                    storage.addRemoteWebApp(draft)
                }
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
                Text(appPendingDeletion?.isRemote == true
                     ? "سيتم حذف بطاقة التطبيق وبيانات WebKit المنفصلة الخاصة به."
                     : "سيتم حذف جميع إصدارات التطبيق ومجلدات Data وDocuments الخاصة به.")
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
        return storage.installedWebApps.filter { app in
            let typeMatches: Bool
            switch selectedFilter {
            case .all: typeMatches = true
            case .local: typeMatches = app.isLocal
            case .remote: typeMatches = app.isRemote
            }
            guard typeMatches else { return false }
            guard !query.isEmpty else { return true }
            return app.name.localizedCaseInsensitiveContains(query)
                || app.id.localizedCaseInsensitiveContains(query)
                || app.version.localizedCaseInsensitiveContains(query)
                || (app.remoteURL?.host?.localizedCaseInsensitiveContains(query) == true)
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

    private func currentApp(withID id: String) -> InstalledWebApp? {
        storage.installedWebApps.first { $0.id == id }
    }

    private func open(_ app: InstalledWebApp) {
        previewApp = storage.markWebAppLaunched(app)
    }
}

private struct EmptyInstalledAppsView: View {
    let importPackage: () -> Void
    let addRemote: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("لا توجد تطبيقات مثبتة")
                .font(.title2.bold())
            Text("ثبّت تطبيق HTML5 وJavaScript محليًا من حزمة .3eweb، أو أضف تطبيق ويب يعمل من الإنترنت.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack {
                Button("تثبيت .3eweb", action: importPackage)
                    .buttonStyle(.borderedProminent)
                Button("إضافة رابط ويب", action: addRemote)
                    .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
