import XCTest

/// Reproduces "add a jar, then the app crashes and won't reopen".
final class AddJarTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
    }

    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }

    private func assertAlive(_ step: String, wait: UInt32 = 4) {
        sleep(wait)
        XCTAssertEqual(app.state, .runningForeground, "App not running after: \(step)")
        print("STEP OK? \(app.state == .runningForeground) :: \(step)")
    }

    private func scrollTo(_ element: XCUIElement, max: Int = 12) {
        var n = 0
        while (!element.exists || !element.isHittable) && n < max {
            app.swipeUp()
            n += 1
        }
    }

    private func openNewJar() {
        let add = app.buttons["Add Jar"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "No Add Jar button")
        add.tap()
        let name = app.textFields["Medication or Supplement"]
        XCTAssertTrue(name.waitForExistence(timeout: 6), "Editor didn't open")
    }

    private func type(_ text: String, into field: XCUIElement) {
        scrollTo(field)
        field.tap()
        field.typeText(text)
    }

    private func save() {
        app.navigationBars.buttons["Save"].firstMatch.tap()
    }

    private func relaunch(_ label: String) {
        app.terminate()
        app.launch()
        assertAlive("relaunch after \(label)", wait: 6)
        print(app.debugDescription.prefix(3000))
    }

    func test1_PlainJar() {
        app.launch()
        allowNotificationsIfAsked()
        assertAlive("first launch")
        openNewJar()
        type("Vitamin D3", into: app.textFields["Medication or Supplement"])
        type("2000 IU", into: app.textFields["e.g. 5 mg"])
        assertAlive("typed plain jar", wait: 1)
        save()
        assertAlive("saved plain jar")
        relaunch("plain jar")
    }

    func test2_AsNeededJar() {
        app.launch()
        allowNotificationsIfAsked()
        openNewJar()
        type("Ibuprofen", into: app.textFields["Medication or Supplement"])
        type("200 mg", into: app.textFields["e.g. 5 mg"])
        let prn = app.switches["As Needed"]
        scrollTo(prn)
        prn.switches.firstMatch.exists ? prn.switches.firstMatch.tap() : prn.tap()
        assertAlive("toggled as needed", wait: 1)
        save()
        assertAlive("saved as-needed jar")
        relaunch("as-needed jar")
    }

    func test3_EffectAndInteraction() {
        app.launch()
        allowNotificationsIfAsked()
        openNewJar()
        type("Adderall IR", into: app.textFields["Medication or Supplement"])
        type("5 mg", into: app.textFields["e.g. 5 mg"])
        let inc = app.buttons["Increment"].firstMatch
        scrollTo(inc)
        if inc.exists { inc.tap(); inc.tap() }
        assertAlive("pills stepper", wait: 1)
        let effect = app.switches["Effect Timeline and Duration"]
        scrollTo(effect)
        effect.switches.firstMatch.exists ? effect.switches.firstMatch.tap() : effect.tap()
        assertAlive("effect toggle", wait: 1)
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Vitamin D3'")).firstMatch
        scrollTo(picker)
        if picker.exists {
            picker.tap()
            let major = app.buttons["Major"].firstMatch
            if major.waitForExistence(timeout: 3) { major.tap() }
        }
        assertAlive("interaction set", wait: 1)
        save()
        assertAlive("saved effect jar")
        relaunch("effect jar")
    }
}
