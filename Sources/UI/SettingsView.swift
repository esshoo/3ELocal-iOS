import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("3e.localweb.injectViewport") private var injectResponsiveViewport = true
    @State private var showingFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("العرض") {
                    Toggle("ملاءمة صفحات غير متجاوبة", isOn: $injectResponsiveViewport)
                    Text("إذا لم يحتوي المشروع على meta viewport يضيف التطبيق إعدادًا مؤقتًا أثناء العرض فقط.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("مجلد 3E") {
                    if let rootURL = storage.rootURL {
                        LabeledContent("المجلد", value: rootURL.lastPathComponent)
                        Text(rootURL.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("اختيار مجلد آخر") { showingFolderPicker = true }
                    Button("فصل مجلد 3E", role: .destructive) {
                        storage.disconnect()
                        dismiss()
                    }
                }

                Section("مفاتيح التوقيع") {
                    NavigationLink {
                        SigningKeysView()
                    } label: {
                        Label("إدارة مفاتيح التوقيع", systemImage: "key.horizontal.fill")
                    }
                    Text("يمكن إنشاء مفتاح على الآيفون أو استيراده من Files أو من Apps/LocalWeb/Keys/Inbox. المفتاح الخاص يُحفظ داخل Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("أمان حزم 3E") {
                    Toggle("السماح بالحزم غير الموقعة (وضع المطور)", isOn: $storage.allowUnsignedPackages)
                    Label(
                        storage.allowUnsignedPackages
                            ? "وضع المطور مفعل: يمكن تثبيت حزم غير موقعة، لكن الحزم ذات التوقيع التالف ستظل مرفوضة."
                            : "الوضع الآمن: لا تُثبت إلا الحزم الموقعة من ناشر موثوق.",
                        systemImage: storage.allowUnsignedPackages ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(storage.allowUnsignedPackages ? Color.orange : Color.green)
                }

                Section("تطبيقات 3E") {
                    AppLinkRow(app: .lidar)
                    AppLinkRow(app: .roomElectrical)
                }

                Section("هوية التطبيق") {
                    LabeledContent("الاسم", value: ThreeEAppIdentity.displayName)
                    LabeledContent("Bundle ID", value: ThreeEAppIdentity.bundleIdentifier)
                    LabeledContent("URL Scheme", value: ThreeEAppIdentity.urlScheme + "://")
                    LabeledContent("App Group مستقبلًا", value: ThreeEAppIdentity.futureAppGroupIdentifier)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                ThreeEFolderPicker { url in
                    storage.connect(to: url)
                    showingFolderPicker = false
                }
            }
        }
    }
}

private struct AppLinkRow: View {
    let app: ThreeEApp

    var body: some View {
        Button {
            guard let url = app.makeURL() else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack {
                Label(app.displayName, systemImage: app == .lidar ? "viewfinder" : "bolt.house")
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
