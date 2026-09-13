import XCTest
@testable import OllaStat

final class UsageParserTests: XCTestCase {
    private func fixtureHTML() throws -> String {
        let bundle = Bundle(for: UsageParserTests.self)
        guard let url = bundle.url(forResource: "settings", withExtension: "html") else {
            XCTFail("Fixture settings.html nicht gefunden")
            throw NSError(domain: "fixture", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesRealSettingsFixture() throws {
        let usage = UsageParser.parse(html: try fixtureHTML())
        XCTAssertNotNil(usage, "Parser muss das echte Settings-Markup lesen können")

        let fiveHour = usage?.window(.fiveHour)
        XCTAssertEqual(fiveHour?.percentUsed ?? -1, 2.2, accuracy: 0.0001)
        XCTAssertEqual(fiveHour?.models, [
            ModelUsage(model: "web search", requests: 2),
            ModelUsage(model: "deepseek-v4-flash:0731", requests: 68),
        ])
        let fiveHourReset = fiveHour?.resetsAt
        XCTAssertNotNil(fiveHourReset)
        let expectedReset = UsageParser.parseISO8601("2026-08-04T09:00:00Z")
        XCTAssertEqual(fiveHourReset, expectedReset)

        let weekly = usage?.window(.weekly)
        XCTAssertEqual(weekly?.percentUsed ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(weekly?.models.count, 3)
        XCTAssertEqual(weekly?.models.first, ModelUsage(model: "glm-5.2", requests: 17))
        XCTAssertNotNil(weekly?.resetsAt)
    }

    func testReturnsNilForPageWithoutUsageMarkers() {
        let html = "<html><body><h1>Sign in</h1></body></html>"
        XCTAssertNil(UsageParser.parse(html: html))
    }

    func testHandlesUnusualAttributeOrderAndQuotes() {
        let html = """
        <div data-usage-meter data-time-ignore>
          <div class="x" aria-label='Weekly usage 13.5% used' data-usage-track>
            <button DATA-MODEL="qwen3:480b" DATA-REQUESTS='42' data-usage-segment></button>
          </div>
        </div>
        <div data-time="2026-08-10T00:00:00Z">Resets</div>
        """
        let usage = UsageParser.parse(html: html)
        let weekly = usage?.window(.weekly)
        XCTAssertEqual(weekly?.percentUsed ?? -1, 13.5, accuracy: 0.0001)
        XCTAssertEqual(weekly?.models.first?.requests, 42)
    }

    func testSkipsUnparseableTracks() {
        let html = """
        <div data-usage-meter>
          <div data-usage-track aria-label="Unknown window 5% used"></div>
        </div>
        <div data-usage-meter>
          <div data-usage-track aria-label="Session usage 7.7% used">
            <div data-usage-segment data-model="llama4" data-requests="3"></div>
          </div>
        </div>
        """
        let usage = UsageParser.parse(html: html)
        XCTAssertEqual(usage?.windows.count, 1)
        XCTAssertEqual(usage?.window(.fiveHour)?.percentUsed, 7.7)
    }

    func testISO8601Parsing() {
        XCTAssertNotNil(UsageParser.parseISO8601("2026-08-04T09:00:00Z"))
        XCTAssertNotNil(UsageParser.parseISO8601("2026-08-04T09:00:00.123Z"))
        XCTAssertNil(UsageParser.parseISO8601("nonsense"))
    }
}

final class HTMLParserTests: XCTestCase {
    func testBuildsParentAndChildRelationships() {
        let html = """
        <html><body>
        <div id="outer"><div id="inner"><span>text</span></div><br><div id="second"></div></div>
        </body></html>
        """
        let root = HTMLParser.parse(html)
        XCTAssertNotNil(root)
        let inner = root?.descendants { $0.attributes["id"] == "inner" }.first
        XCTAssertEqual(inner?.parent?.attributes["id"], "outer")
        let second = root?.descendants { $0.attributes["id"] == "second" }.first
        XCTAssertEqual(second?.parent?.attributes["id"], "outer")
        // br must not become a parent of the following sibling
        XCTAssertEqual(second?.parent?.children.count, 3)
    }

    func testVoidAndSelfClosingElements() {
        let html = "<div><img src=\"x.png\"><input type=text value=hi><hr/></div>"
        let root = HTMLParser.parse(html)
        let div = root?.descendants { $0.name == "div" }.first
        XCTAssertEqual(div?.children.count, 3)
        XCTAssertEqual(div?.children.first?.attributes["src"], "x.png")
        XCTAssertEqual(div?.children[1].attributes["value"], "hi")
    }

    func testSkipsScriptAndStyleContent() {
        let html = "<div><script>var a = \"<div id=inside-script>\";</script><style>a{}</style><div id=\"real\"></div></div>"
        let root = HTMLParser.parse(html)
        let real = root?.descendants { $0.attributes["id"] == "real" }.first
        XCTAssertNotNil(real)
        XCTAssertEqual(root?.descendants { $0.attributes["id"] == "inside-script" }.count, 0)
    }

    func testDecodesEntities() {
        let html = "<a title=\"Tom &amp; Jerry &#65;\">x</a>"
        let root = HTMLParser.parse(html)
        let anchor = root?.descendants { $0.name == "a" }.first
        XCTAssertEqual(anchor?.attributes["title"], "Tom & Jerry A")
    }

    func testBooleanAttributes() {
        let html = "<div data-usage-meter><div></div></div>"
        let root = HTMLParser.parse(html)
        let meter = root?.descendants { $0.attribute("data-usage-meter") != nil }.first
        XCTAssertNotNil(meter)
    }
}

final class ThresholdTrackerTests: XCTestCase {
    func testFiresOnUpwardCrossingsOnly() {
        var tracker = ThresholdTracker()
        let thresholds = [50.0, 75.0, 90.0, 100.0]

        var window = UsageWindow(kind: .fiveHour, percentUsed: 10, resetsAt: nil, models: [])
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [])

        window.percentUsed = 55
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [50])

        window.percentUsed = 60
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [])

        window.percentUsed = 92
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [75, 90])

        window.percentUsed = 101
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [100])
    }

    func testRearmsAfterReset() {
        var tracker = ThresholdTracker()
        let thresholds = [50.0, 75.0]

        var window = UsageWindow(kind: .weekly, percentUsed: 80, resetsAt: nil, models: [])
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [50, 75])

        // Window reset: usage drops back to a low value.
        window.percentUsed = 2
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [])

        window.percentUsed = 62
        XCTAssertEqual(tracker.crossings(for: window, thresholds: thresholds), [50])
    }

    func testWindowsAreIndependent() {
        var tracker = ThresholdTracker()
        let thresholds = [50.0]
        let fiveHour = UsageWindow(kind: .fiveHour, percentUsed: 60, resetsAt: nil, models: [])
        let weekly = UsageWindow(kind: .weekly, percentUsed: 60, resetsAt: nil, models: [])
        XCTAssertEqual(tracker.crossings(for: fiveHour, thresholds: thresholds), [50])
        XCTAssertEqual(tracker.crossings(for: weekly, thresholds: thresholds), [50])
    }
}