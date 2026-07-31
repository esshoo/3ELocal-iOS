import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @State private var showingFolderPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 36)

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.blue.gradient)
                            .frame(width: 116, height: 116)
                        Text("3E")
                            .font(.system(size: 46, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 8) {
                        Text("3ELocal")
                            .font(.largeTitle.bold())
                        Text("شغّل مشاريع الويب المحلية من مجلد 3E المشترك")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(icon: "folder.badge.plus", title: "مجلد موحّد", detail: "اختر مجلد 3E نفسه المستخدم في تطبيقاتك الثلاثة.")
                        FeatureRow(icon: "network", title: "خادم محلي", detail: "تشغيل HTML وCSS وJavaScript وWebAssembly عبر HTTP محلي.")
                        FeatureRow(icon: "iphone.and.arrow.forward", title: "متوافق مع الأجهزة", detail: "عرض تلقائي على iPhone وiPad والوضعين الرأسي والأفقي.")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("ربط مجلد 3E", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("أنشئ مجلدًا باسم 3E داخل iCloud Drive أو أي موفّر ملفات، ثم اختره هنا. سينشئ التطبيق داخله Apps/LocalWeb تلقائيًا.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("إعداد 3ELocal")
            .sheet(isPresented: $showingFolderPicker) {
                ThreeEFolderPicker { url in
                    storage.connect(to: url)
                    showingFolderPicker = false
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
