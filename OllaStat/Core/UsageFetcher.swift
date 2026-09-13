import Foundation

enum FetchFailure: Error, LocalizedError, Equatable {
    case sessionExpired
    case http(status: Int)
    case network(String)
    case noCookie

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Session abgelaufen — neuen Cookie in den Einstellungen hinterlegen."
        case .http(let status):
            return "HTTP-Fehler \(status) beim Abruf von ollama.com"
        case .network(let message):
            return "Netzwerkfehler: \(message)"
        case .noCookie:
            return "Kein Session-Cookie hinterlegt."
        }
    }
}

/// Fetches the logged-in settings page HTML from ollama.com.
final class UsageFetcher {
    struct Configuration {
        var settingsURL = URL(string: "https://ollama.com/settings")!
        var timeout: TimeInterval = 15
        var userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
        var cookieName = "__Secure-session"
        var protocolClasses: [AnyClass]? = nil
    }

    let configuration: Configuration
    private let session: URLSession
    private let delegate: RedirectGuard

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        delegate = RedirectGuard()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout * 2
        config.protocolClasses = configuration.protocolClasses
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Fetches the settings page and returns its HTML.
    func fetchSettingsHTML(cookie: String) async throws -> String {
        var request = URLRequest(url: configuration.settingsURL)
        request.setValue("\(configuration.cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        delegate.redirectedToSignin = false

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FetchFailure.network(error.localizedDescription)
        }

        if delegate.redirectedToSignin {
            throw FetchFailure.sessionExpired
        }

        guard let http = response as? HTTPURLResponse else {
            throw FetchFailure.network("Keine HTTP-Antwort")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw FetchFailure.sessionExpired
        }
        if (300..<400).contains(http.statusCode) {
            // URLProtocol-basierte Antworten (Tests) durchlaufen den Redirect-Delegate
            // nicht — deshalb auch die 3xx-Antwort selbst prüfen.
            let location = http.allHeaderFields.reduce("") { partial, pair in
                (pair.key as? String)?.lowercased() == "location" ? (pair.value as? String ?? "") : partial
            }.lowercased()
            if location.contains("signin") || response.url?.path.lowercased().contains("signin") == true {
                throw FetchFailure.sessionExpired
            }
        }
        guard http.statusCode == 200 else {
            throw FetchFailure.http(status: http.statusCode)
        }

        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let html, html.contains("data-usage-track") else {
            // A 200 without usage markers usually means we were served a
            // sign-in page without a redirect.
            if html?.lowercased().contains("signin") == true {
                throw FetchFailure.sessionExpired
            }
            throw FetchFailure.network("Unerwartete Antwort der Einstellungsseite")
        }
        return html
    }

    /// Validates a cookie by attempting a real fetch.
    func validate(cookie: String) async throws -> Bool {
        _ = try await fetchSettingsHTML(cookie: cookie)
        return true
    }

    private final class RedirectGuard: NSObject, URLSessionDataDelegate {
        var redirectedToSignin = false

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            let location = (response.value(forHTTPHeaderField: "Location") ?? "").lowercased()
            if location.contains("signin") || request.url?.path.lowercased().contains("signin") == true {
                redirectedToSignin = true
                completionHandler(nil)
            } else {
                completionHandler(request)
            }
        }
    }
}