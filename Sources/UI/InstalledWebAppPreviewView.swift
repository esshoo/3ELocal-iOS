import SwiftUI
import UIKit

struct InstalledWebAppPreviewView: View {
    let app: InstalledWebApp

    @Environment(\.dismiss) private var dismiss
    @StateObject private var server = LocalHTTPServer()
    @StateObject private var webModel = WebViewControllerModel()
    @AppStorage("3e.localweb.injectViewport") private var injectResponsiveViewport = true

    var body: some View {
        NavigationStack {
            Group {
                switch server.state {
                case .stopped, .starting:
                    ProgressView("تشغيل التطبيق المحلي…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 52))
                            .foregroundStyle(.orange)
                        Text("تعذر تشغيل التطبيق")
                            .font(.title2.bold())
                        Text(message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .running:
                    if let url = server.localURL {
                        WebViewContainer(
                            url: url,
                            injectResponsiveViewport: injectResponsiveViewport,
                            model: webModel
                        )
                        .id(injectResponsiveViewport)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .top) {
                            if webModel.isLoading {
                                ProgressView().padding(8)
                            }
                        }
                    } else {
                        ProgressView()
                    }
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
                    Menu {
                        Toggle("ملاءمة شاشة الجهاز", isOn: $injectResponsiveViewport)
                        Text("الإصدار \(app.version)")
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
            }
            .safeAreaInset(edge: .bottom) {
                if let networkURL = server.networkURL {
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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            server.start(
                projectRoot: app.activePackageURL,
                indexURL: app.entryURL,
                preferredPort: LocalHTTPServer.stablePort(for: app.id)
            )
        }
        .onDisappear {
            server.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
