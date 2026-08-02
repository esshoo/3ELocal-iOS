import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RemoteWebAppEditorView: View {
    let save: (RemoteWebAppDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var name = ""
    @State private var appDescription = ""
    @State private var iconData: Data?
    @State private var navigationPolicy: WebAppManifest.NavigationPolicy = .sameHost
    @State private var allowedDomainsText = ""
    @State private var isFetchingMetadata = false
    @State private var showingIconImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("رابط التطبيق") {
                    TextField("https://example.com/app", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button {
                        fetchMetadata()
                    } label: {
                        if isFetchingMetadata {
                            HStack {
                                ProgressView()
                                Text("جلب الاسم والأيقونة…")
                            }
                        } else {
                            Label("جلب بيانات الموقع", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(normalizedURL == nil || isFetchingMetadata)
                }

                Section("بيانات التطبيق") {
                    HStack(spacing: 14) {
                        iconPreview
                        VStack(alignment: .leading, spacing: 8) {
                            Button(iconData == nil ? "اختيار أيقونة" : "تغيير الأيقونة") {
                                showingIconImporter = true
                            }
                            if iconData != nil {
                                Button("إزالة الأيقونة", role: .destructive) {
                                    iconData = nil
                                }
                                .font(.caption)
                            }
                        }
                    }

                    TextField("اسم التطبيق", text: $name)
                    TextField("وصف اختياري", text: $appDescription, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("التنقل والأمان") {
                    Picker("فتح الروابط", selection: $navigationPolicy) {
                        Text("نفس الموقع فقط").tag(WebAppManifest.NavigationPolicy.sameHost)
                        Text("نطاقات محددة").tag(WebAppManifest.NavigationPolicy.allowedDomains)
                        Text("أي موقع داخل التطبيق").tag(WebAppManifest.NavigationPolicy.unrestricted)
                    }

                    if navigationPolicy == .allowedDomains {
                        TextField("api.example.com, files.example.com", text: $allowedDomainsText, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("افصل النطاقات بفاصلة. نطاق رابط البداية يضاف تلقائيًا.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if navigationPolicy == .sameHost {
                        Text("الروابط الخارجية ستُفتح في المتصفح بدل الانتقال إليها داخل التطبيق.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Label("التطبيق يحتاج اتصالًا بالإنترنت ولا يتم تنزيل محتوى الموقع.", systemImage: "wifi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("إضافة تطبيق ويب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") { saveDraft() }
                        .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showingIconImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importIcon(from: url)
                case .failure(let error):
                    errorMessage = "تعذر اختيار الأيقونة: \(error.localizedDescription)"
                }
            }
            .alert("3ELocal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var iconPreview: some View {
        Group {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.blue.opacity(0.12))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private var normalizedURL: URL? {
        var value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("https://") {
            value = "https://" + value
        }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private var canSave: Bool {
        normalizedURL != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFetchingMetadata
    }

    private func fetchMetadata() {
        guard let url = normalizedURL else { return }
        isFetchingMetadata = true
        errorMessage = nil

        Task {
            do {
                let metadata = try await RemoteWebAppMetadataFetcher.fetch(from: url)
                await MainActor.run {
                    urlText = metadata.startURL.absoluteString
                    if let fetchedName = metadata.name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = fetchedName
                    }
                    if let fetchedDescription = metadata.appDescription,
                       appDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appDescription = fetchedDescription
                    }
                    if iconData == nil { iconData = metadata.iconData }
                    if allowedDomainsText.isEmpty, let host = metadata.startURL.host {
                        allowedDomainsText = host
                    }
                    isFetchingMetadata = false
                }
            } catch {
                await MainActor.run {
                    isFetchingMetadata = false
                    errorMessage = "تعذر جلب بيانات الموقع. يمكنك إدخال الاسم والأيقونة يدويًا.\n\n\(error.localizedDescription)"
                }
            }
        }
    }

    private func importIcon(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 8 * 1_024 * 1_024,
                  let image = UIImage(data: data),
                  let png = image.pngData() else {
                throw WebAppPackageError.invalidIcon(url.lastPathComponent)
            }
            iconData = png
        } catch {
            errorMessage = "تعذر قراءة الأيقونة: \(error.localizedDescription)"
        }
    }

    private func saveDraft() {
        guard let url = normalizedURL else {
            errorMessage = "أدخل رابط HTTPS صالحًا."
            return
        }

        let domains = allowedDomainsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        save(RemoteWebAppDraft(
            name: name,
            startURL: url,
            appDescription: appDescription,
            iconData: iconData,
            navigationPolicy: navigationPolicy,
            allowedDomains: navigationPolicy == .allowedDomains ? domains : []
        ))
        dismiss()
    }
}
