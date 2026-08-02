import SwiftUI

struct WebAppDownloadsView: View {
    @EnvironmentObject private var storage: ThreeEStorageManager
    @ObservedObject private var downloads: WebAppDownloadManager
    @State private var showingDirectDownload = false

    init(downloads: WebAppDownloadManager) {
        self.downloads = downloads
    }

    var body: some View {
        NavigationStack {
            Group {
                if downloads.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                        Text("لا توجد تنزيلات")
                            .font(.title2.bold())
                        Text("نزّل تطبيقًا من فهرس 3E أو استخدم رابط حزمة مباشر.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("تنزيل من رابط") { showingDirectDownload = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(downloads.items) { item in
                            DownloadItemRow(
                                item: item,
                                pause: { downloads.pause(item.id) },
                                resume: { downloads.resume(item.id) },
                                retry: { downloads.retry(item.id) },
                                cancel: { downloads.cancel(item.id) },
                                install: { storage.installDownloadedPackage(item) },
                                remove: { downloads.remove(item.id) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("التنزيلات")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        downloads.clearFinished()
                    } label: {
                        Image(systemName: "checkmark.circle.badge.xmark")
                    }
                    .disabled(downloads.items.allSatisfy {
                        ![.installed, .failed, .cancelled].contains($0.state)
                    })

                    Button {
                        showingDirectDownload = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showingDirectDownload) {
                DirectPackageDownloadView()
                    .environmentObject(storage)
            }
            .alert("3ELocal", isPresented: messageBinding) {
                Button("حسنًا", role: .cancel) {
                    storage.operationMessage = nil
                    storage.errorMessage = nil
                }
            } message: {
                Text(storage.errorMessage ?? storage.operationMessage ?? "")
            }
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { storage.errorMessage != nil || storage.operationMessage != nil },
            set: { presented in
                if !presented {
                    storage.errorMessage = nil
                    storage.operationMessage = nil
                }
            }
        )
    }
}

private struct DownloadItemRow: View {
    let item: WebAppDownloadItem
    let pause: () -> Void
    let resume: () -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let install: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.sourceURL.host ?? item.sourceURL.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(stateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
            }

            if item.state == .downloading || item.state == .paused {
                ProgressView(value: item.progress)
                HStack {
                    Text(bytesText)
                    Spacer()
                    if item.expectedBytes > 0 {
                        Text("\(Int(item.progress * 100))%")
                    }
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }

            if let error = item.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if item.canPause {
                    Button("إيقاف مؤقت", action: pause)
                }
                if item.canResume {
                    Button("استكمال", action: resume)
                }
                if item.canRetry {
                    Button("إعادة المحاولة", action: retry)
                }
                if item.canInstall {
                    Button("فحص وتثبيت", action: install)
                        .buttonStyle(.borderedProminent)
                }
                if item.state == .downloading || item.state == .paused || item.state == .queued {
                    Button("إلغاء", role: .destructive, action: cancel)
                }
                Spacer()
                if [.installed, .failed, .cancelled].contains(item.state) {
                    Button(role: .destructive, action: remove) {
                        Image(systemName: "trash")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private var stateText: String {
        switch item.state {
        case .queued: return "في الانتظار"
        case .downloading: return "جارٍ التنزيل"
        case .paused: return "متوقف مؤقتًا"
        case .downloaded: return "جاهز للتثبيت"
        case .installing: return "جارٍ التثبيت"
        case .installed: return "تم التثبيت"
        case .failed: return "فشل"
        case .cancelled: return "ملغي"
        }
    }

    private var stateIcon: String {
        switch item.state {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .downloaded: return "shippingbox.circle.fill"
        case .installing: return "gearshape.2.fill"
        case .installed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .installed: return .green
        case .failed: return .red
        case .cancelled, .paused: return .orange
        default: return .blue
        }
    }

    private var bytesText: String {
        let received = ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)
        guard item.expectedBytes > 0 else { return received }
        let expected = ByteCountFormatter.string(fromByteCount: item.expectedBytes, countStyle: .file)
        return "\(received) / \(expected)"
    }
}
