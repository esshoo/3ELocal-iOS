import SwiftUI

enum ProjectFilter: String, CaseIterable, Identifiable {
    case all = "الكل"
    case favorites = "المفضلة"
    case recent = "الأخيرة"

    var id: String { rawValue }
}

struct ProjectLibraryView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @EnvironmentObject private var library: ProjectLibraryStore
    @EnvironmentObject private var router: DeepLinkRouter

    @State private var searchText = ""
    @State private var filter: ProjectFilter = .all
    @State private var previewProject: WebProject?
    @State private var showingSettings = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 300), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if storage.projects.isEmpty {
                    EmptyProjectsView(
                        createSample: { storage.createSampleProject() },
                        refresh: { storage.refreshProjects() }
                    )
                } else {
                    ScrollView {
                        Picker("التصفية", selection: $filter) {
                            ForEach(ProjectFilter.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredProjects) { project in
                                ProjectCardView(
                                    project: project,
                                    isFavorite: library.isFavorite(project),
                                    open: { open(project) },
                                    toggleFavorite: { library.toggleFavorite(project) }
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("3ELocal")
            .searchable(text: $searchText, prompt: "ابحث عن مشروع")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { storage.refreshProjects() } label: { Image(systemName: "arrow.clockwise") }
                    Menu {
                        Button { storage.createSampleProject() } label: {
                            Label("إنشاء مشروع تجريبي", systemImage: "doc.badge.plus")
                        }
                        Button { showingSettings = true } label: {
                            Label("الإعدادات", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fullScreenCover(item: $previewProject) { project in
                ProjectPreviewView(project: project)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(storage)
            }
            .onAppear { handlePendingDeepLink() }
            .onChange(of: router.pendingRelativePath) { _ in handlePendingDeepLink() }
            .alert("3ELocal", isPresented: errorBinding) {
                Button("حسنًا", role: .cancel) {
                    storage.errorMessage = nil
                    router.lastError = nil
                }
            } message: {
                Text(storage.errorMessage ?? router.lastError ?? "Unknown error")
            }
        }
    }

    private var filteredProjects: [WebProject] {
        var result = storage.projects
        switch filter {
        case .all:
            break
        case .favorites:
            result = result.filter { library.isFavorite($0) }
        case .recent:
            result = result.compactMap { project in
                library.recentRank(for: project).map { ($0, project) }
            }
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.relativePath.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { storage.errorMessage != nil || router.lastError != nil },
            set: { presented in
                if !presented {
                    storage.errorMessage = nil
                    router.lastError = nil
                }
            }
        )
    }

    private func open(_ project: WebProject) {
        library.markOpened(project)
        previewProject = project
    }

    private func handlePendingDeepLink() {
        guard let path = router.pendingRelativePath else { return }
        storage.refreshProjects()
        if let project = storage.project(matchingRelativePath: path) {
            open(project)
            router.clear()
        } else {
            router.lastError = "لم يتم العثور على مشروع يطابق المسار: \(path)"
            router.clear()
        }
    }
}


private struct EmptyProjectsView: View {
    let createSample: () -> Void
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("لا توجد مشاريع")
                .font(.title2.bold())
            Text("ضع كل مشروع في مجلد مستقل يحتوي على index.html داخل Apps/LocalWeb/Projects أو Shared/Projects.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("إنشاء مشروع تجريبي", action: createSample)
                .buttonStyle(.borderedProminent)
            Button("تحديث", action: refresh)
                .buttonStyle(.bordered)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
