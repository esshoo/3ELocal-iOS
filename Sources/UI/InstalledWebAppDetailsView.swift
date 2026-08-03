import SwiftUI
import UIKit

struct InstalledWebAppDetailsView: View {
    let app: InstalledWebApp
    let isOnline: Bool
    let open: () -> Void
    let rollback: () -> Void
    let uninstall: () -> Void

    @EnvironmentObject private var storage: ThreeEStorageManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingSigner = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        InstalledWebAppIconView(app: app, size: 74)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(app.name)
                                .font(.title3.bold())
                            HStack(spacing: 8) {
                                TypeBadge(app: app)
                                PackageTrustBadge(app: app)
                                if app.isRemote {
                                    Label(isOnline ? "متصل" : "دون اتصال", systemImage: isOnline ? "wifi" : "wifi.slash")
                                        .font(.caption)
                                        .foregroundStyle(isOnline ? Color.green : Color.orange)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    if let description = app.appDescription, !description.isEmpty {
                        Text(description)
                    }
                }

                Section("التشغيل") {
                    Button {
                        dismiss()
                        open()
                    } label: {
                        Label("فتح التطبيق", systemImage: "play.fill")
                    }

                    if let remoteURL = app.remoteURL {
                        LabeledContent("الرابط") {
                            Text(remoteURL.absoluteString)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                        ShareLink(item: remoteURL) {
                            Label("مشاركة الرابط", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.url = remoteURL
                        } label: {
                            Label("نسخ الرابط", systemImage: "doc.on.doc")
                        }
                    }
                }

                Section("المعلومات") {
                    LabeledContent("النوع", value: app.typeDisplayName)
                    LabeledContent("الإصدار", value: app.version)
                    LabeledContent("الحجم", value: ByteCountFormatter.string(fromByteCount: app.storageSizeBytes, countStyle: .file))
                    LabeledContent("تاريخ التثبيت", value: formatted(app.installedAt))
                    LabeledContent("آخر تحديث", value: formatted(app.updatedAt))
                    LabeledContent("آخر تشغيل", value: app.lastLaunchedAt.map(formatted) ?? "لم يُفتح بعد")
                    LabeledContent("مرات التشغيل", value: String(app.launchCount))
                    LabeledContent("المعرّف") {
                        Text(app.id)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if app.isLocal {
                    Section("الثقة والتوقيع") {
                        LabeledContent("الحالة", value: trustName)
                        if let publisher = app.publisherDisplayName {
                            LabeledContent("الناشر", value: publisher)
                        }
                        if let keyID = app.packageTrust.keyID {
                            LabeledContent("مفتاح التوقيع") {
                                Text(keyID).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                        if let verifiedAt = app.packageTrust.verifiedAt {
                            LabeledContent("آخر تحقق", value: formatted(verifiedAt))
                        }
                        Text(trustDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            showingSigner = true
                        } label: {
                            Label("توقيع وتصدير من الآيفون", systemImage: "signature")
                        }
                    }
                }

                if app.isRemote {
                    Section("سياسة التنقل") {
                        LabeledContent("السياسة", value: navigationPolicyName)
                        if !app.effectiveAllowedHosts.isEmpty {
                            ForEach(app.effectiveAllowedHosts.sorted(), id: \.self) { host in
                                Label(host, systemImage: "checkmark.shield")
                                    .font(.caption.monospaced())
                            }
                        }
                        Text("كل تطبيق إنترنت يستخدم ملف تعريف WebKit مستقلًا على iOS 17 أو أحدث.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("الإدارة") {
                    if app.isLocal, app.previousVersion != nil {
                        Button(action: rollback) {
                            Label("الرجوع للإصدار السابق", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button(role: .destructive, action: uninstall) {
                        Label("حذف التطبيق وبياناته", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("تفاصيل التطبيق")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSigner) {
                SignInstalledWebAppView(app: app)
                    .environmentObject(storage)
            }
        }
    }

    private var trustName: String {
        switch app.packageTrust.state {
        case .trusted: return "حزمة موقعة وموثوقة"
        case .unsigned: return "حزمة غير موقعة"
        case .remote: return "تطبيق ويب من رابط"
        }
    }

    private var trustDescription: String {
        switch app.packageTrust.state {
        case .trusted:
            return "تم التحقق من توقيع Ed25519 ومن بصمة كل ملف داخل الحزمة."
        case .unsigned:
            return "هذه حزمة قديمة أو ثُبتت أثناء تفعيل وضع المطور. لا يمكن ضمان مصدر ملفاتها."
        case .remote:
            return "المحتوى يأتي مباشرة من موقع الإنترنت ولا يستخدم توقيع حزم 3E المحلية."
        }
    }

    private var navigationPolicyName: String {
        switch app.navigationPolicy {
        case .sameHost: return "نفس الموقع"
        case .allowedDomains: return "نطاقات محددة"
        case .unrestricted: return "غير مقيد"
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct TypeBadge: View {
    let app: InstalledWebApp

    var body: some View {
        Label(app.typeDisplayName, systemImage: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(app.isRemote ? Color.purple : Color.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((app.isRemote ? Color.purple : Color.blue).opacity(0.12), in: Capsule())
    }

    private var iconName: String {
        app.isRemote ? "cloud" : "internaldrive"
    }
}
