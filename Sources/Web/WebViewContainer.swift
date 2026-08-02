import SwiftUI
import WebKit
import UIKit

@MainActor
final class WebViewControllerModel: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentURL: URL?

    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() {
        errorMessage = nil
        webView?.reloadFromOrigin()
    }

    func clearError() { errorMessage = nil }

    fileprivate func update(
        from webView: WKWebView,
        isLoading: Bool? = nil,
        errorMessage: String? = nil,
        clearError: Bool = false
    ) {
        self.webView = webView
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
        if let isLoading { self.isLoading = isLoading }
        if clearError { self.errorMessage = nil }
        if let errorMessage { self.errorMessage = errorMessage }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let injectResponsiveViewport: Bool
    @ObservedObject var model: WebViewControllerModel
    var appIdentifier: String? = nil
    var navigationPolicy: WebAppManifest.NavigationPolicy = .unrestricted
    var allowedHosts: Set<String> = []
    var openExternalLinksInSystem = true

    func makeCoordinator() -> Coordinator {
        Coordinator(
            model: model,
            navigationPolicy: navigationPolicy,
            allowedHosts: allowedHosts,
            openExternalLinksInSystem: openExternalLinksInSystem
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended

        if let appIdentifier {
            configuration.websiteDataStore = WebAppDataStoreIdentifier.persistentStore(for: appIdentifier)
        }

        if injectResponsiveViewport {
            let script = WKUserScript(
                source: """
                (function() {
                    if (!document.querySelector('meta[name="viewport"]')) {
                        var meta = document.createElement('meta');
                        meta.name = 'viewport';
                        meta.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
                        (document.head || document.documentElement).appendChild(meta);
                    }
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(script)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        model.webView = webView
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.navigationPolicy = navigationPolicy
        context.coordinator.allowedHosts = allowedHosts
        context.coordinator.openExternalLinksInSystem = openExternalLinksInSystem
        if webView.url == nil, !webView.isLoading {
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebViewControllerModel
        var navigationPolicy: WebAppManifest.NavigationPolicy
        var allowedHosts: Set<String>
        var openExternalLinksInSystem: Bool

        init(
            model: WebViewControllerModel,
            navigationPolicy: WebAppManifest.NavigationPolicy,
            allowedHosts: Set<String>,
            openExternalLinksInSystem: Bool
        ) {
            self.model = model
            self.navigationPolicy = navigationPolicy
            self.allowedHosts = allowedHosts
            self.openExternalLinksInSystem = openExternalLinksInSystem
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let destination = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = destination.scheme?.lowercased() ?? ""
            guard scheme == "http" || scheme == "https" else {
                if openExternalLinksInSystem, UIApplication.shared.canOpenURL(destination) {
                    UIApplication.shared.open(destination)
                }
                decisionHandler(.cancel)
                return
            }

            if isAllowed(destination) {
                decisionHandler(.allow)
                return
            }

            if openExternalLinksInSystem,
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(destination)
                decisionHandler(.cancel)
                return
            }

            Task { @MainActor in
                model.update(
                    from: webView,
                    errorMessage: "تم منع الانتقال إلى نطاق غير مصرح به: \(destination.host ?? destination.absoluteString)"
                )
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url else { return nil }
            if isAllowed(url) {
                webView.load(navigationAction.request)
            } else if openExternalLinksInSystem {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in model.update(from: webView, isLoading: true, clearError: true) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in model.update(from: webView, isLoading: false, clearError: true) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                model.update(from: webView, isLoading: false, errorMessage: error.localizedDescription)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                model.update(from: webView, isLoading: false, errorMessage: error.localizedDescription)
            }
        }

        private func isAllowed(_ url: URL) -> Bool {
            if navigationPolicy == .unrestricted { return true }
            guard let host = url.host?.lowercased() else { return false }
            return allowedHosts.contains { allowed in
                host == allowed || host.hasSuffix("." + allowed)
            }
        }
    }
}
