import SwiftUI
import UIKit

struct WebAppCatalogView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @State private var showingDirectDownload = false
    @State private var searchText = ""
    @FocusState private var catalogURLFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("مصدر التطبيقات") {
                    TextField("رابط catalog.json باستخدام HTTPS", text: $storage.catalogURLString, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($catalogURLFocused)
                        .onSubmit {
                            dismissCatalogKeyboard()
                            Task { await storage.fetchCatalog() }
                        }

                    Button {
                        dismissCatalogKeyboard()
                        Task { await storage.fetchCatalog() }
                    } label: {
                        if storage.isLoadingCatalog {
                            HStack {
                                ProgressView()
                                Text("جارٍ فحص الفهرس…")
                            }
                        } else {
                            Label("فحص التطبيقات والتحديثات", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    .disabled(storage.isLoadingCatalog)

                    if let checked = storage.catalogLastCheckedAt {
                        LabeledContent("آخر فحص", value: checked.formatted(date: .abbreviated, time: .shortened))
                    }
                    if storage.availableUpdateCount > 0 {
                        Label("يتوفر \(storage.availableUpdateCount) تحديث", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                if storage.catalogEntries.isEmpty {
                    Section {
                        VStack(spacing: 14) {
                            Image(systemName: "square.grid.3x3")
                                .font(.system(size: 46))
                                .foregroundStyle(.secondary)
                            Text("لم يتم تحميل فهرس")
                                .font(.title3.bold())
                            Text("أدخل رابط catalog.json الخاص بك ثم اضغط فحص التطبيقات والتحديثات.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                } else {
                    Section(storage.catalogName ?? "تطبيقات 3E") {
                        ForEach(filteredEntries) { entry in
                            CatalogEntryRow(
                                entry: entry,
                                iconURL: storage.catalogIconURL(for: entry),
                                installedApp: storage.installedWebApps.first { $0.id == entry.id },
                                isIgnored: storage.isUpdateIgnored(appID: entry.id, version: entry.version),
                                download: { storage.downloadCatalogEntry(entry) },
                                ignore: { storage.ignoreUpdate(appID: entry.id, version: entry.version) },
                                restore: { storage.clearIgnoredUpdate(appID: entry.id) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("متجر 3E الخاص")
            .searchable(text: $searchText, prompt: "ابحث في الفهرس")
            .scrollDismissesKeyboard(.interactively)
            .background(KeyboardDismissTapView())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") { dismissCatalogKeyboard() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismissCatalogKeyboard()
                        showingDirectDownload = true
                    } label: {
                        Image(systemName: "link.badge.plus")
                    }
                    .accessibilityLabel("تنزيل حزمة من رابط")
                }
            }
            .sheet(isPresented: $showingDirectDownload) {
                DirectPackageDownloadView()
                    .environmentObject(storage)
            }
            .alert("3ELocal", isPresented: messageBinding) {
                Button("حسنًا", role: .cancel) {
                    storage.operationMessage = nil
                    storage.errorMessage = nil
                }
            } message: {
                Text(storage.errorMessage ?? storage.operationMessage ?? "")
            }
            .onDisappear {
                dismissCatalogKeyboard()
            }
            .task {
                if storage.catalogEntries.isEmpty,
                   !storage.catalogURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await storage.fetchCatalog()
                }
            }
        }
    }

    private func dismissCatalogKeyboard() {
        catalogURLFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var filteredEntries: [WebAppCatalogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return storage.catalogEntries }
        return storage.catalogEntries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.version.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) == true)
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

private struct CatalogEntryRow: View {
    let entry: WebAppCatalogEntry
    let iconURL: URL?
    let installedApp: InstalledWebApp?
    let isIgnored: Bool
    let download: () -> Void
    let ignore: () -> Void
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: iconURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.blue.opacity(0.12))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.name).font(.headline)
                    Spacer()
                    Text("v\(entry.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let description = entry.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(entry.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                actionArea
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var actionArea: some View {
        if !entry.isRuntimeCompatible {
            Label("يتطلب إصدارًا أحدث من 3ELocal", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let installedApp {
            let comparison = WebAppVersion.compare(entry.version, installedApp.version)
            if comparison == .orderedDescending {
                if isIgnored {
                    HStack {
                        Label("تم تجاهل هذا الإصدار", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("إظهاره", action: restore)
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Button("تنزيل التحديث", action: download)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("تجاهل", action: ignore)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } else if comparison == .orderedSame {
                Label("مثبت ومحدّث", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("لديك إصدار أحدث: \(installedApp.version)", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } else {
            Button("تنزيل للتثبيت", action: download)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
