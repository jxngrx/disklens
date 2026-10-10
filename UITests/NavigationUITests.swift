import XCTest

/// Drives the treemap on a generated fixture folder (never the real disk).
final class NavigationUITests: XCTestCase {
    var fixture: URL!
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("disklens-fixtures/ui-\(UUID().uuidString.prefix(6))")
        let files: [(String, Int)] = [
            ("big/a.bin", 30), ("big/inner/b.bin", 12), ("big/inner/deep/c.bin", 4), ("mid/m.bin", 10), ("small/s.bin", 3),
        ]
        for (rel, mb) in files {
            let url = fixture.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: mb << 20).write(to: url)
        }
        app.launchArguments = ["-scanRoot", fixture.path, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Scan complete"].waitForExistence(timeout: 20))
    }

    override func tearDownWithError() throws {
        app.terminate()
        if fixture.path.contains("/disklens-fixtures/") { try? FileManager.default.removeItem(at: fixture) }
    }

    func crumb(_ name: String) -> XCUIElement { app.buttons["crumb-\(name)"] }

    func testClickBoxDrillsIntoRightFolder() {
        // Squarify places the biggest child ("big") at the top-left corner.
        let map = app.descendants(matching: .any)["treemap"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).click()
        XCTAssertTrue(crumb("big").waitForExistence(timeout: 5))
        // Again: biggest child of big is "inner" (16 MB vs a.bin 30 MB file -> a.bin is a file, so click inner via sidebar).
        app.buttons["row-inner"].click()
        XCTAssertTrue(crumb("inner").waitForExistence(timeout: 5))
    }

    func testBreadcrumbAndBack() {
        app.buttons["row-big"].click()
        XCTAssertTrue(crumb("big").waitForExistence(timeout: 5))
        app.buttons["row-inner"].click()
        XCTAssertTrue(crumb("inner").waitForExistence(timeout: 5))
        app.buttons["row-deep"].click()
        XCTAssertTrue(crumb("deep").waitForExistence(timeout: 5))

        // Breadcrumb jumps straight to an ancestor.
        crumb("big").click()
        XCTAssertTrue(crumb("deep").waitForNonExistence(timeout: 5))
        XCTAssertFalse(crumb("inner").exists)

        // Esc goes back to where we were (deep), ⌘[ goes back again (big).
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(crumb("deep").waitForExistence(timeout: 5))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(crumb("deep").waitForNonExistence(timeout: 5))
        XCTAssertTrue(crumb("inner").exists)

        // ⌘↑ goes to the parent.
        app.typeKey(.upArrow, modifierFlags: .command)
        XCTAssertTrue(crumb("inner").waitForNonExistence(timeout: 5))
        XCTAssertTrue(crumb("big").exists)

        // Toolbar back button.
        app.buttons["back"].click()
        XCTAssertTrue(crumb("inner").waitForExistence(timeout: 5))
    }
}
