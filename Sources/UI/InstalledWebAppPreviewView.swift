import SwiftUI
import UIKit

struct InstalledWebAppPreviewView: View {
    let app: InstalledWebApp

    @Environment(\.dismiss) private var dismiss
    @StateObject private var server = LocalHTTPServer()
    @StateObject private var webModel = WebViewControllerModel()
    @StateObject private var network = NetworkStatusMonitor()
    @AppStorage("3e.localweb.injectViewport") private var injectResponsiveViewport = true

    var body: some View {
        NavigationStack {
            Group {
                if app.isRemote {
                    remoteContent
                } else {
                    localContent
                }
            }
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("إغلاق") { dismiss() }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { webModel.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!webModel.canGoBack)
                    Button { webModel.goForward() } label: { Image(systemName: "chevron.forward") }
                        .disabled(!webModel.canGoForward)
                    Button { webModel.reload() } label: { Image(systemName: "arrow.clockwise") }
                    appMenu
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomStatus
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if app.isLocal, let entryURL = app.entryURL {
                server.start(
                    projectRoot: app.activePackageURL,
                    indexURL: entryURL,
                    preferredPort: LocalHTTPServer.stablePort(for: app.id)
                )
            }
        }
        .onDisappear {
            server.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private var localContent: some View {
        switch server.state {
        case .stopped, .starting:
            ProgressView("تشغيل التطبيق المحلي…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            errorState(title: "تعذر تشغيل التطبيق", message: message)

        case .running:
            if let url = server.localURL {
                webView(url: url, remote: false)
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var remoteContent: some View {
        if !network.isOnline {
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                Text("لا يوجد اتصال بالإنترنت")
                    .font(.title2.bold())
                Text("هذا تطبيق ويب مرتبط بالإنترنت. أعد الاتصال ثم اضغط إعادة المحاولة.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("إعادة المحاولة") { webModel.reload() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let url = app.remoteURL {
            webView(url: url, remote: true)
        } else {
            errorState(title: "الرابط غير صالح", message: app.record.activeManifest.startURL ?? "")
        }
    }

    private func webView(url: URL, remote: Bool) -> some View {
        WebViewContainer(
            url: url,
            injectResponsiveViewport: injectResponsiveViewport,
            model: webModel,
            appIdentifier: remote ? app.id : nil,
            navigationPolicy: remote ? app.navigationPolicy : .unrestricted,
            allowedHosts: remote ? app.effectiveAllowedHosts : [],
            openExternalLinksInSystem: true
        )
        .id("\(injectResponsiveViewport)-\(app.id)")
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if webModel.isLoading {
                    ProgressView()
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                }
                if let error = webModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .lineLimit(3)
                        Spacer()
                        Button {
                            webModel.clearError()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }
            }
        }
    }

    private func errorState(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appMenu: some View {
        Menu {
            Toggle("ملاءمة شاشة الجهاز", isOn: $injectResponsiveViewport)
            Text("النوع: \(app.typeDisplayName)")
            Text("الإصدار \(app.version)")

            if let remoteURL = app.remoteURL {
                ShareLink(item: remoteURL) {
                    Label("مشاركة رابط التطبيق", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.url = remoteURL
                } label: {
                    Label("نسخ الرابط", systemImage: "doc.on.doc")
                }
                Button {
                    UIApplication.shared.open(remoteURL)
                } label: {
                    Label("فتح في المتصفح", systemImage: "safari")
                }
            }

            if let networkURL = server.networkURL {
                ShareLink(item: networkURL) {
                    Label("مشاركة على الشبكة", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.url = networkURL
                } label: {
                    Label("نسخ رابط الشبكة", systemImage: "doc.on.doc")
                }
            }

            if let localURL = server.localURL {
                Button {
                    UIPasteboard.general.url = localURL
                } label: {
                    Label("نسخ الرابط المحلي", systemImage: "link")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var bottomStatus: some View {
        if app.isRemote {
            HStack(spacing: 10) {
                Image(systemName: network.isOnline ? "wifi" : "wifi.slash")
                    .foregroundStyle(network.isOnline ? Color.green : Color.orange)
                Text(network.isOnline ? (app.remoteURL?.host ?? "متصل") : "دون اتصال")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                Text(app.navigationPolicy == .unrestricted ? "تنقل مفتوح" : "تنقل محمي")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        } else if let networkURL = server.networkURL {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                Text(networkURL.absoluteString)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                ShareLink(item: networkURL) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}
