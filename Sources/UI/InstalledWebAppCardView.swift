import SwiftUI
import UIKit

struct InstalledWebAppCardView: View {
    let app: InstalledWebApp
    let open: () -> Void
    let rollback: () -> Void
    let uninstall: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    InstalledWebAppIconView(app: app, size: 54)
                    Spacer()
                    Text("v\(app.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.secondary.opacity(0.1), in: Capsule())
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

                    Text(app.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Label("فتح التطبيق", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: open) {
                Label("فتح", systemImage: "play.fill")
            }
            if app.previousVersion != nil {
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
                Image(systemName: "globe")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.blue.opacity(0.12))
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
