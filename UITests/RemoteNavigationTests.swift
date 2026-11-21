import XCTest

/// The Siri Remote moves the focus where a viewer expects: from the rail
/// into the page and back.
final class RemoteNavigationTests: XCTestCase {
    private let remote = XCUIRemote.shared

    private func focusedLabel(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true")).label
    }

    func testRightLeavesTheRailForThePage() {
        let app = XCUIApplication()
        app.launchArguments = ["-veltrioInstall", "https://v3-cinemeta.strem.io/manifest.json"]
        app.launch()
        sleep(8)
        let start = focusedLabel(app)
        remote.press(.right)
        sleep(1)
        let after = focusedLabel(app)
        XCTAssertNotEqual(start, after, "focus stayed on \(start)")
        remote.press(.left)
        sleep(1)
        let back = focusedLabel(app)
        print("focus: \(start) → \(after) → \(back)")
        XCTAssertEqual(back, start, "back in the rail on \(back), not on the open section")
    }

    func testEverySectionTakesTheFocus() {
        let app = XCUIApplication()
        app.launch()
        sleep(8)
        var seen: [String] = []
        for _ in 0..<3 {
            remote.press(.down)
            sleep(1)
            remote.press(.select)   // open the section
            sleep(3)
            let section = focusedLabel(app)
            remote.press(.right)
            sleep(1)
            let inPage = focusedLabel(app)
            seen.append("\(section) → \(inPage)")
            XCTAssertNotEqual(section, inPage, "right did nothing on \(section)")
            remote.press(.left)
            sleep(1)
        }
        print("sections: \(seen.joined(separator: " | "))")
    }
}
