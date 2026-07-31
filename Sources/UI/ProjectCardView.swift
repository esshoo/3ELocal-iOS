import SwiftUI

struct ProjectCardView: View {
    let project: WebProject
    let isFavorite: Bool
    let open: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: "globe")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 50, height: 50)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    Spacer()

                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "إزالة من المفضلة" : "إضافة إلى المفضلة")
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(project.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(project.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Label("فتح المشروع", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: open) { Label("فتح", systemImage: "play.fill") }
            Button(action: toggleFavorite) {
                Label(isFavorite ? "إزالة من المفضلة" : "إضافة إلى المفضلة", systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }
}
