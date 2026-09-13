import SwiftUI
import WebKit

struct LoginSheetView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case browsing
        case saving
        case success
        case failed(String)
    }

    @State private var phase: Phase = .browsing
    @State private var cookieHandled = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bei ollama.com anmelden")
                    .font(.headline)
                Text("Melde dich an (z. B. mit GitHub). Nach dem Login fängt OllaStat das Session-Cookie automatisch ab und speichert es im Schlüsselbund — nichts kopieren nötig.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Hinweis: Bei E-Mail-Anmeldung den Code im Fenster eingeben, nicht den Link aus der Mail im Browser öffnen.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            ZStack {
                OllamaLoginWebView(onCookieDetected: handleCookie)
                if case .saving = phase {
                    Color(nsColor: .windowBackgroundColor).opacity(0.85)
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Cookie wird geprüft und gespeichert …")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                switch phase {
                case .browsing:
                    Label("Warte auf Anmeldung …", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .success:
                    Label("✓ Angemeldet — Cookie gespeichert.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                case .failed(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                case .saving:
                    EmptyView()
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 500, height: 660)
    }

    private func handleCookie(_ cookie: String) {
        guard !cookieHandled else { return }
        cookieHandled = true
        phase = .saving
        Task { await save(cookie: cookie) }
    }

    private func save(cookie: String) async {
        do {
            let fetcher = UsageFetcher()
            _ = try await fetcher.validate(cookie: cookie)
            try KeychainStore.saveCookie(cookie)
            await UsageMonitor.shared.refreshOnce()
            phase = .success
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch let failure as FetchFailure {
            phase = .failed(failure.localizedDescription)
            cookieHandled = false
        } catch {
            phase = .failed(error.localizedDescription)
            cookieHandled = false
        }
    }
}

struct OllamaLoginWebView: NSViewRepresentable {
    let onCookieDetected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieDetected: onCookieDetected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if let url = URL(string: "https://ollama.com/signin") {
            webView.load(URLRequest(url: url))
        }
        context.coordinator.webView = webView
        webView.configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        private let onCookieDetected: (String) -> Void
        private var fired = false
        weak var webView: WKWebView?

        init(onCookieDetected: @escaping (String) -> Void) {
            self.onCookieDetected = onCookieDetected
        }

        func cookiesChanged(in cookieStore: WKHTTPCookieStore) {
            checkCookies(cookieStore)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies(webView.configuration.websiteDataStore.httpCookieStore)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // OAuth-Popups (GitHub/Google) in dasselbe Webview umleiten
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func checkCookies(_ store: WKHTTPCookieStore) {
            guard !fired else { return }
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.fired else { return }
                if let cookie = cookies.first(where: {
                    $0.name == "__Secure-session"
                        && !$0.value.isEmpty
                        && $0.domain.hasSuffix("ollama.com")
                }) {
                    self.fired = true
                    self.onCookieDetected(cookie.value)
                }
            }
        }
    }
}