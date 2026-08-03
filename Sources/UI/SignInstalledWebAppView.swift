import SwiftUI

struct SignInstalledWebAppView: View {
    let app: InstalledWebApp

    @EnvironmentObject private var storage: ThreeEStorageManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var keyStore = LocalSigningKeyStore.shared
    @State private var selectedKeyID: String?
    @State private var packageValidity: PackageValidityPreset = .lifetime
    @State private var result: WebAppSigningResult?
    @State private var isSigning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("التطبيق") {
                    LabeledContent("الاسم", value: app.name)
                    LabeledContent("الإصدار", value: app.version)
                    LabeledContent("المعرّف", value: app.id)
                }

                Section("مفتاح التوقيع") {
                    if availableKeys.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "key.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("لا يوجد مفتاح فعال").font(.headline)
                            Text("أنشئ أو استورد مفتاحًا من الإعدادات أولًا.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        Picker("المفتاح", selection: $selectedKeyID) {
                            Text("اختر مفتاحًا").tag(String?.none)
                            ForEach(availableKeys) { key in
                                Text("\(key.publisherName) — \(key.keyID)").tag(String?.some(key.keyID))
                            }
                        }
                    }
                }

                Section("صلاحية الحزمة") {
                    Picker("المدة", selection: $packageValidity) {
                        ForEach(PackageValidityPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Text("مدة الحزمة اختيارية ومستقلة عن مدة المفتاح. عند انتهائها يرفض 3ELocal تثبيت الحزمة أو تشغيل نسخة موقعة منها بعد التحقق.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        sign()
                    } label: {
                        HStack {
                            Label("توقيع وتصدير .3eweb", systemImage: "signature")
                            Spacer()
                            if isSigning { ProgressView() }
                        }
                    }
                    .disabled(selectedKeyID == nil || isSigning)
                }

                if let result {
                    Section("الحزمة الموقعة") {
                        LabeledContent("الملف") {
                            Text(result.outputURL.lastPathComponent)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("المفتاح", value: result.key.keyID)
                        LabeledContent("وقت التوقيع", value: result.signedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent(
                            "انتهاء الحزمة",
                            value: result.packageExpiresAt?.formatted(date: .abbreviated, time: .shortened) ?? "بدون انتهاء"
                        )
                        ShareLink(item: result.outputURL) {
                            Label("مشاركة الحزمة", systemImage: "square.and.arrow.up")
                        }
                        Text(result.outputURL.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("التوقيع من الآيفون")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .onAppear {
                if selectedKeyID == nil {
                    selectedKeyID = availableKeys.first?.keyID
                }
            }
            .alert("تعذر توقيع الحزمة", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var availableKeys: [LocalSigningKeyMetadata] {
        keyStore.keys.filter { $0.canSign }
    }

    private func sign() {
        guard let selectedKeyID,
              let key = availableKeys.first(where: { $0.keyID == selectedKeyID }),
              let outputDirectory = storage.signedPackagesURL else {
            errorMessage = "مجلد 3E غير متصل أو المفتاح غير متاح."
            return
        }
        isSigning = true
        defer { isSigning = false }
        do {
            result = try OnDeviceWebAppSigner.signInstalledApp(
                app,
                key: key,
                packageValidity: packageValidity,
                outputDirectory: outputDirectory
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
