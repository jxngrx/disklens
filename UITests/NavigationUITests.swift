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
    /// Sidebar rows surface as outline rows/cells, not buttons.
    func row(_ name: String) -> XCUIElement { app.descendants(matching: .any)["row-\(name)"].firstMatch }

    func testClickBoxDrillsIntoRightFolder() {
        // Squarify places the biggest child ("big") at the top-left corner.
        let map = app.descendants(matching: .any)["treemap"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).click()
        XCTAssertTrue(crumb("big").waitForExistence(timeout: 5))
        // Again: biggest child of big is "inner" (16 MB vs a.bin 30 MB file -> a.bin is a file, so click inner via sidebar).
        row("inner").click()
        XCTAssertTrue(crumb("inner").waitForExistence(timeout: 5))
    }

    func testBreadcrumbAndBack() {
        row("big").click()
        XCTAssertTrue(crumb("big").waitForExistence(timeout: 5))
        row("inner").click()
        XCTAssertTrue(crumb("inner").waitForExistence(timeout: 5))
        row("deep").click()
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

/// Clean confirm sheet on a fixture project. Runs with DISKLENS_DRY_RUN=1 and a fixture quarantine,
/// and only cancels or cleans fixture files.
final class CleanSheetUITests: XCTestCase {
    var fixture: URL!
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("disklens-fixtures/ui-clean-\(UUID().uuidString.prefix(6))")
        let files: [(String, Int)] = [("web/package.json", 0), ("web/node_modules/react/index.js", 20), ("web/src/app.js", 1)]
        for (rel, mb) in files {
            let url = fixture.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: max(10, mb << 20)).write(to: url)
        }
        app.launchEnvironment["DISKLENS_DRY_RUN"] = "1"
        app.launchArguments = ["-scanRoot", fixture.path, "-rulesHome", fixture.path,
                               "-quarantineRoot", fixture.appendingPathComponent(".q").path, "-openPath", fixture.path + "/web"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Scan complete"].waitForExistence(timeout: 20))
    }

    override func tearDownWithError() throws {
        app.terminate()
        if fixture.path.contains("/disklens-fixtures/") { try? FileManager.default.removeItem(at: fixture) }
    }

    func testConfirmSheetCancelThenClean() {
        let map = app.descendants(matching: .any)["treemap"]
        // node_modules is the biggest box: top-left.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).rightClick()
        app.menuItems["Clean Project build artifact…"].click()
        XCTAssertTrue(app.staticTexts["clean-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["clean-item-node_modules"].exists)
        app.buttons["clean-cancel"].click()
        XCTAssertTrue(app.staticTexts["clean-title"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path + "/web/node_modules"))

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).rightClick()
        app.menuItems["Clean Project build artifact…"].click()
        app.buttons["clean-confirm"].click()
        XCTAssertTrue(app.staticTexts["clean-message"].waitForExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/web/node_modules"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path + "/web/src/app.js"))
    }
}
