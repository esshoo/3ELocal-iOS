import SwiftUI

struct DirectPackageDownloadView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section("رابط الحزمة") {
                    TextField("https://example.com/App.3eweb", text: $urlText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button {
                        showingScanner = true
                    } label: {
                        Label("مسح QR", systemImage: "qrcode.viewfinder")
                    }
                }

                Section {
                    Text("سيتم تنزيل الملف إلى مجلد Apps/LocalWeb/Downloads، ثم يمكنك فحصه وتثبيته من تبويب التنزيلات.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("تنزيل حزمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تنزيل") {
                        storage.downloadPackage(from: urlText)
                        if storage.errorMessage == nil { dismiss() }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRCodeScannerView { value in
                    urlText = value
                }
            }
        }
    }
}
