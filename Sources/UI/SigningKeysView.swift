import SwiftUI
import UniformTypeIdentifiers

struct SigningKeysView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @StateObject private var keyStore = LocalSigningKeyStore.shared
    @State private var showingCreate = false
    @State private var showingImporter = false
    @State private var importLifetime: SigningKeyLifetimePreset = .oneYear
    @State private var importRequiresPresence = true
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label(
                    "المفتاح الخاص يُحفظ داخل Keychain ولا يبقى كملف عادي بعد الاستيراد.",
                    systemImage: "key.horizontal.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    showingCreate = true
                } label: {
                    Label("إنشاء مفتاح على هذا الآيفون", systemImage: "plus.circle")
                }
            }

            Section("استيراد مفتاح") {
                Picker("مدة صلاحية المفتاح", selection: $importLifetime) {
                    ForEach(SigningKeyLifetimePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Toggle("طلب Face ID أو رمز الجهاز عند التوقيع", isOn: $importRequiresPresence)

                Button {
                    showingImporter = true
                } label: {
                    Label("اختيار ملف .3ekey أو PEM", systemImage: "doc.badge.plus")
                }

                Button(action: importFromKeysInbox) {
                    Label("استيراد من مجلد Keys/Inbox", systemImage: "folder.badge.plus")
                }
                .disabled(storage.signingKeysInboxURL == nil)

                if let inbox = storage.signingKeysInboxURL {
                    Text(inbox.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("المفاتيح المحفوظة") {
                if keyStore.keys.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "key.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("لا توجد مفاتيح").font(.headline)
                        Text("أنشئ مفتاحًا جديدًا أو استورد مفتاح الناشر الحالي.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(keyStore.keys) { key in
                        SigningKeyRow(key: key)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(key)
                                } label: {
                                    Label("حذف الخاص", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("مفاتيح التوقيع")
        .sheet(isPresented: $showingCreate) {
            CreateSigningKeyView { result in
                showingCreate = false
                switch result {
                case .success(let key):
                    message = "تم إنشاء المفتاح \(key.keyID)."
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let key = try keyStore.importKey(
                        from: url,
                        lifetime: importLifetime,
                        requiresUserPresence: importRequiresPresence
                    )
                    message = "تم استيراد المفتاح \(key.keyID) إلى Keychain."
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("تم", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("حسنًا", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .alert("تعذر تنفيذ العملية", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func importFromKeysInbox() {
        guard let inbox = storage.signingKeysInboxURL else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: inbox,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { ["3ekey", "pem"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !files.isEmpty else {
                errorMessage = "لا توجد ملفات .3ekey أو PEM داخل Keys/Inbox."
                return
            }

            var imported = 0
            var failures: [String] = []
            for url in files {
                do {
                    _ = try keyStore.importKey(
                        from: url,
                        lifetime: importLifetime,
                        requiresUserPresence: importRequiresPresence
                    )
                    imported += 1
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if failures.isEmpty {
                message = "تم استيراد \(imported) مفتاح وحذف ملفات الاستيراد من Inbox."
            } else {
                errorMessage = "تم استيراد \(imported). فشل:\n" + failures.joined(separator: "\n")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ key: LocalSigningKeyMetadata) {
        do {
            try keyStore.delete(key)
            message = "تم حذف المفتاح الخاص \(key.keyID) من الجهاز، مع الاحتفاظ بالمفتاح العام للتحقق من الحزم القديمة."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SigningKeyRow: View {
    let key: LocalSigningKeyMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.publisherName).font(.headline)
                    Text(key.keyID).font(.caption.monospaced())
                }
                Spacer()
                Label(
                    statusText,
                    systemImage: statusIcon
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            }
            Text("الناشر: \(key.publisherID)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("البصمة: \(key.fingerprint)")
                .font(.caption2.monospaced())
                .textSelection(.enabled)
            HStack {
                Label(
                    key.requiresUserPresence && (key.privateKeyAvailable ?? true) ? "محمي بالمصادقة" : "Keychain / تحقق عام",
                    systemImage: key.requiresUserPresence ? "faceid" : "lock.fill"
                )
                Spacer()
                Text(expirationText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }


    private var statusText: String {
        if !(key.privateKeyAvailable ?? true) { return "تحقق فقط" }
        return key.isExpired ? "منتهي" : "فعال"
    }

    private var statusIcon: String {
        if !(key.privateKeyAvailable ?? true) { return "checkmark.shield.fill" }
        return key.isExpired ? "xmark.seal.fill" : "checkmark.seal.fill"
    }

    private var statusColor: Color {
        if !(key.privateKeyAvailable ?? true) { return .blue }
        return key.isExpired ? .red : .green
    }

    private var expirationText: String {
        guard let expiresAt = key.expiresAt else { return "مدى الحياة" }
        return "ينتهي: \(expiresAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct CreateSigningKeyView: View {
    let completion: (Result<LocalSigningKeyMetadata, Error>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var publisherID = "com.essam.3e"
    @State private var publisherName = "3E / Essam"
    @State private var keyID = "3e-iphone-\(Self.defaultKeySuffix)"
    @State private var lifetime: SigningKeyLifetimePreset = .oneYear
    @State private var requiresPresence = true

    var body: some View {
        NavigationStack {
            Form {
                Section("هوية الناشر") {
                    TextField("Publisher ID", text: $publisherID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("اسم الناشر", text: $publisherName)
                    TextField("Key ID", text: $keyID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("الحماية والصلاحية") {
                    Picker("المدة", selection: $lifetime) {
                        ForEach(SigningKeyLifetimePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Toggle("طلب Face ID أو رمز الجهاز", isOn: $requiresPresence)
                    Text("بعد انتهاء المدة يتوقف المفتاح عن إنشاء توقيعات جديدة، بينما تظل الحزم التي وُقعت قبل انتهائه صالحة.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("إنشاء مفتاح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") {
                        do {
                            let key = try LocalSigningKeyStore.shared.generateKey(
                                publisherID: publisherID.trimmingCharacters(in: .whitespacesAndNewlines),
                                publisherName: publisherName.trimmingCharacters(in: .whitespacesAndNewlines),
                                keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
                                lifetime: lifetime,
                                requiresUserPresence: requiresPresence
                            )
                            completion(.success(key))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    private static var defaultKeySuffix: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }
}
