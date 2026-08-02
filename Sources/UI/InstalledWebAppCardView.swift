import SwiftUI
import UIKit

struct InstalledWebAppCardView: View {
    let app: InstalledWebApp
    let isOnline: Bool
    let availableUpdate: WebAppCatalogEntry?
    let open: () -> Void
    let details: () -> Void
    let downloadUpdate: () -> Void
    let ignoreUpdate: () -> Void
    let rollback: () -> Void
    let uninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                InstalledWebAppIconView(app: app, size: 54)
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    TypeBadge(app: app)
                    PackageTrustBadge(app: app)
                    if app.isRemote {
                        Label(isOnline ? "متصل" : "دون اتصال", systemImage: isOnline ? "wifi" : "wifi.slash")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isOnline ? Color.green : Color.orange)
                    } else {
                        Text("v\(app.version)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let availableUpdate {
                        Label("تحديث v\(availableUpdate.version)", systemImage: "arrow.down.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let description = app.appDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(app.isRemote ? (app.remoteURL?.host ?? app.id) : app.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                Label("فتح التطبيق", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                if availableUpdate != nil {
                    Button(action: downloadUpdate) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("تنزيل التحديث")
                }
                Button(action: details) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تفاصيل التطبيق")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: open)
        .contextMenu {
            Button(action: open) {
                Label("فتح", systemImage: "play.fill")
            }
            Button(action: details) {
                Label("التفاصيل", systemImage: "info.circle")
            }
            if let availableUpdate {
                Button(action: downloadUpdate) {
                    Label("تنزيل التحديث \(availableUpdate.version)", systemImage: "arrow.down.circle")
                }
                Button(action: ignoreUpdate) {
                    Label("تجاهل هذا الإصدار", systemImage: "eye.slash")
                }
            }
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
}

struct PackageTrustBadge: View {
    let app: InstalledWebApp

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch app.packageTrust.state {
        case .trusted: return "موثوق"
        case .unsigned: return "غير موقّع"
        case .remote: return "ويب"
        }
    }

    private var icon: String {
        switch app.packageTrust.state {
        case .trusted: return "checkmark.shield.fill"
        case .unsigned: return "exclamationmark.triangle.fill"
        case .remote: return "globe"
        }
    }

    private var color: Color {
        switch app.packageTrust.state {
        case .trusted: return .green
        case .unsigned: return .orange
        case .remote: return .purple
        }
    }
}

struct InstalledWebAppIconView: View {
    let app: InstalledWebApp
    let size: CGFloat

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: app.isRemote ? "globe" : "shippingbox")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(app.isRemote ? Color.purple : Color.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background((app.isRemote ? Color.purple : Color.blue).opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var loadedImage: UIImage? {
        guard let iconURL = app.iconURL,
              let data = try? Data(contentsOf: iconURL) else {
            return nil
        }
        return UIImage(data: data)
    }
}
