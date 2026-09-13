import XCTest
@testable import OllaStat

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)
        guard let handler = MockURLProtocol.handler, let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: data)
            client.urlProtocolDidFinishLoading(self)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class UsageFetcherTests: XCTestCase {
    private let marker = #"<div data-usage-meter><div data-usage-track aria-label="Session usage 5.0% used"></div></div>"#

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeFetcher() -> UsageFetcher {
        UsageFetcher(configuration: UsageFetcher.Configuration(protocolClasses: [MockURLProtocol.self]))
    }

    private func response(_ status: Int, url: URL, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    func testRedirectToSigninThrowsSessionExpired() async {
        MockURLProtocol.handler = { request in
            (self.response(302, url: request.url!, headers: ["Location": "https://ollama.com/signin"]), Data())
        }
        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchSettingsHTML(cookie: "abc")
            XCTFail("Expected sessionExpired")
        } catch let error as FetchFailure {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test401ThrowsSessionExpired() async {
        MockURLProtocol.handler = { request in
            (self.response(401, url: request.url!), Data())
        }
        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchSettingsHTML(cookie: "abc")
            XCTFail("Expected sessionExpired")
        } catch let error as FetchFailure {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test500ThrowsHTTPStatus() async {
        MockURLProtocol.handler = { request in
            (self.response(500, url: request.url!), Data())
        }
        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchSettingsHTML(cookie: "abc")
            XCTFail("Expected http(500)")
        } catch let error as FetchFailure {
            XCTAssertEqual(error, .http(status: 500))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test200SigninPageThrowsSessionExpired() async {
        MockURLProtocol.handler = { request in
            (self.response(200, url: request.url!), Data("<html>redirecting to /signin, please log in</html>".utf8))
        }
        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetchSettingsHTML(cookie: "abc")
            XCTFail("Expected sessionExpired")
        } catch let error as FetchFailure {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidPageReturnsHTML() async throws {
        MockURLProtocol.handler = { request in
            (self.response(200, url: request.url!), Data(self.marker.utf8))
        }
        let fetcher = makeFetcher()
        let html = try await fetcher.fetchSettingsHTML(cookie: "abc")
        XCTAssertTrue(html.contains("data-usage-track"))
    }

    func testSendsCookieAndUserAgentHeaders() async throws {
        MockURLProtocol.handler = { request in
            (self.response(200, url: request.url!), Data(self.marker.utf8))
        }
        let fetcher = makeFetcher()
        _ = try await fetcher.fetchSettingsHTML(cookie: "secret-cookie")
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Secure-session=secret-cookie")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), fetcher.configuration.userAgent)
        XCTAssertEqual(request.url?.absoluteString, "https://ollama.com/settings")
    }

    func testValidateReturnsTrueOnValidPage() async throws {
        MockURLProtocol.handler = { request in
            (self.response(200, url: request.url!), Data(self.marker.utf8))
        }
        let fetcher = makeFetcher()
        let valid = try await fetcher.validate(cookie: "abc")
        XCTAssertTrue(valid)
    }

    func testValidateThrowsOnSigninRedirect() async {
        MockURLProtocol.handler = { request in
            (self.response(302, url: request.url!, headers: ["Location": "https://ollama.com/signin"]), Data())
        }
        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.validate(cookie: "abc")
            XCTFail("Expected sessionExpired")
        } catch let error as FetchFailure {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}