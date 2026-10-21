import XCTest

/// Shared helpers: launching with the seed, timed steps with screenshots, soft checks that keep going.
class MedJarsUITestCase: XCTestCase {
    let app = XCUIApplication()
    static var stepNumber = 0
    var failures = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func record(_ issue: XCTIssue) {
        failures += 1
        super.record(issue)
    }

    func mark(_ text: String) {
        print(String(format: "MARK %.3f %@", Date().timeIntervalSince1970, text))
    }

    func launch(seed: Bool = true, extra: [String] = []) {
        let env = ProcessInfo.processInfo.environment
        var args = ["-perfHarness", "-captureStdout", "-askedForNotifications", "YES"]
        if seed { args.append("-seedFullTest") }
        app.launchArguments = args + extra
        if let s = env["SEED_PATH"] { app.launchEnvironment["SEED_PATH"] = s }
        if let p = env["PERF_DIR"] { app.launchEnvironment["PERF_DIR"] = p }
        let start = Date()
        app.launch()
        let ok = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        mark(String(format: "LAUNCHED %@ in %.0fms ok=%@", name, Date().timeIntervalSince(start) * 1000, ok ? "yes" : "no"))
        dismissSystemAlerts()
    }

    func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow"] {
            let b = springboard.buttons[label]
            if b.exists { b.tap() }
        }
    }

    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    func step(_ title: String, snapAfter: Bool = true, _ body: () -> Void) -> Double {
        Self.stepNumber += 1
        let n = String(format: "%03d", Self.stepNumber)
        mark("STEP BEGIN \(n) \(title)")
        dismissSystemAlerts()
        let before = failures
        let start = Date()
        XCTContext.runActivity(named: "\(n) \(title)") { _ in body() }
        let ms = Date().timeIntervalSince(start) * 1000
        if snapAfter { snap("\(n) \(title)") }
        mark(String(format: "STEP END %@ %.0fms %@ :: %@", n, ms, failures == before ? "OK" : "FAIL", title))
        return ms
    }

    private var treeDumps = 0

    func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        if cond() { return }
        mark("CHECK FAIL: \(msg)")
        if treeDumps < 25 {
            treeDumps += 1
            print("TREE BEGIN \(msg)\n\(String(app.debugDescription.prefix(6000)))\nTREE END")
        }
        XCTFail(msg, file: file, line: line)
    }

    @discardableResult
    func waitFor(_ e: XCUIElement, _ timeout: Double = 5, _ msg: String) -> Bool {
        let ok = e.waitForExistence(timeout: timeout)
        check(ok, msg)
        return ok
    }

    /// How long until the element shows up, in ms (or -1 when it never does).
    func timeUntil(_ e: XCUIElement, _ timeout: Double = 10) -> Double {
        let start = Date()
        return e.waitForExistence(timeout: timeout) ? Date().timeIntervalSince(start) * 1000 : -1
    }

    func label(_ text: String) -> NSPredicate { NSPredicate(format: "label == %@", text) }
    func labelContains(_ text: String) -> NSPredicate { NSPredicate(format: "label CONTAINS %@", text) }
    func labelBegins(_ text: String) -> NSPredicate { NSPredicate(format: "label BEGINSWITH %@", text) }

    func button(_ text: String) -> XCUIElement { app.buttons[text].firstMatch }
    func text(_ text: String) -> XCUIElement { app.staticTexts[text].firstMatch }
    func navBar(_ title: String) -> XCUIElement { app.navigationBars[title].firstMatch }

    /// The match lowest on screen, for labels that repeat (the plus menu's Log vs. a card's Log).
    func lowest(_ query: XCUIElementQuery) -> XCUIElement? {
        let all = query.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return all.max { $0.frame.maxY < $1.frame.maxY }
    }

    func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        if waitFor(b, 5, "tab \(name) exists") { b.tap() }
    }

    func tapIf(_ e: XCUIElement, _ timeout: Double = 3) -> Bool {
        if e.waitForExistence(timeout: timeout) && e.isHittable { e.tap(); return true }
        return false
    }

    func scrollTo(_ e: XCUIElement, max: Int = 10, up: Bool = true) {
        var n = 0
        while (!e.exists || !e.isHittable) && n < max {
            if up { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
            n += 1
        }
        n = 0
        while (!e.exists || !e.isHittable) && n < max {
            if up { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            n += 1
        }
    }

    /// Answers the early or late question if the log sheet asks it.
    func confirmIfAsked() {
        for t in ["Yes, Log It Now", "Log Anyway"] {
            let b = app.buttons[t].firstMatch
            if b.waitForExistence(timeout: 1.5) && b.isHittable { b.tap(); return }
        }
        let late = app.buttons.matching(labelBegins("At ")).firstMatch
        if late.exists && late.isHittable { late.tap() }
    }

    /// The big button at the bottom of the log sheet.
    func tapLogSheetButton() {
        let b = app.buttons.matching(NSPredicate(format: "(label BEGINSWITH 'Log ' AND NOT (label BEGINSWITH 'Log or')) OR label == 'Log Anyway' OR label == 'Save Changes' OR label == 'Delete Dose'"))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.max { $0.frame.maxY < $1.frame.maxY }
        b?.tap()
        confirmIfAsked()
    }

    func scrollToTop() {
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
    }

    func goBack() {
        let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        if back.exists && back.isHittable { back.tap(); return }
        let named = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Back' OR identifier CONTAINS 'Back'")).firstMatch
        if named.exists && named.isHittable { named.tap(); return }
        // Fallback: tapping the selected tab again goes back to its first screen.
        let selected = app.tabBars.buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch
        if selected.exists { selected.tap() }
    }

    /// The Log button in a substance page's Log bar (Log, Log Extra).
    func pageLogButton() -> XCUIElement? {
        lowest(app.buttons.matching(NSPredicate(format: "label == 'Log' OR label == 'Log Extra'")))
    }

    /// Closes whatever sheet is up.
    func closeSheet() {
        for t in ["Cancel", "Done", "Close"] {
            let b = app.navigationBars.buttons[t].firstMatch
            if b.exists && b.isHittable { b.tap(); usleep(800_000); return }
        }
        app.swipeDown(velocity: .fast)
        usleep(800_000)
    }

    /// Responsive check: tab switch to Home and the Edit button appears.
    @discardableResult
    func responsive(_ context: String) -> Double {
        let start = Date()
        app.tabBars.buttons["Home"].tap()
        let ok = app.navigationBars.buttons["Edit"].firstMatch.waitForExistence(timeout: 20)
        let ms = Date().timeIntervalSince(start) * 1000
        mark(String(format: "RESPONSIVE %@ %.0fms ok=%@", context, ms, ok ? "yes" : "no"))
        check(ok && ms < 5000, "app responsive after \(context) (\(Int(ms)) ms)")
        check(app.state == .runningForeground, "app still running after \(context)")
        return ms
    }

    func goHome() {
        closeSheet()
        tab("Home")
        tab("Home")
        scrollToTop()
    }

    /// Taps the plus button (closed state).
    func tapPlus() {
        let main = app.buttons["Log or Schedule"].firstMatch
        if main.waitForExistence(timeout: 3) && main.isHittable { main.tap() } else { check(false, "plus button found") }
    }

    func plusMenuLog() -> Bool {
        guard let log = lowest(app.buttons.matching(label("Log"))) else { check(false, "plus menu Log"); return false }
        log.tap()
        return true
    }
}

// MARK: - Feature tests

final class A_HomeTests: MedJarsUITestCase {
    func test01_LaunchAndScroll() {
        step("Home on launch") {
            launch()
            waitFor(app.navigationBars.buttons["Edit"].firstMatch, 15, "Home Edit button")
            check(app.buttons["Log or Schedule"].exists, "plus button on Home")
        }
        for i in 1...4 {
            step("Home scrolled \(i)") { app.swipeUp(velocity: .slow) }
        }
        step("Home back to top") { scrollToTop() }
    }

    func test02_TileTaps() {
        launch()
        step("Up Next tile opens Schedule") {
            let time = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^(Due |Tomorrow |Tmrw )?[0-9]{1,2}:[0-9]{2} [AP]M$")).firstMatch
            if waitFor(time, 5, "Up Next time text") { time.tap() }
            waitFor(navBar("Schedule"), 5, "Schedule after Up Next tap")
        }
        goHome()
        step("Today tile opens Schedule") {
            let today = app.descendants(matching: .any).matching(labelContains("doses taken today")).firstMatch
            if waitFor(today, 5, "Today tile") { today.tap() }
            waitFor(navBar("Schedule"), 5, "Schedule after Today tap")
        }
        goHome()
        step("Missed tile popout") {
            let missed = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' Missed' OR label == 'Nothing missed'")).firstMatch
            if waitFor(missed, 5, "Missed tile text") { missed.tap() }
            waitFor(navBar("Missed"), 5, "Missed sheet")
            check(app.buttons.matching(labelBegins("Log at ")).count > 0, "Missed sheet has Log at buttons")
        }
        closeSheet()
        step("Working Now tile popout") {
            let t = text("Working Now")
            scrollTo(t)
            if waitFor(t, 5, "Working Now tile") { t.tap() }
            waitFor(navBar("Working Now"), 5, "Working Now sheet")
            check(app.staticTexts.matching(labelBegins("Adderall")).count > 0, "Working Now lists Adderall")
        }
        closeSheet()
        step("Caffeine tile menu adds coffee") {
            let cup = app.buttons.matching(labelContains("milligrams of caffeine")).firstMatch
            scrollTo(cup)
            let before = cup.label
            if waitFor(cup, 5, "Caffeine tile button") { cup.tap() }
            let coffee = button("Coffee, 95 mg")
            if waitFor(coffee, 4, "Coffee preset in caffeine menu") { coffee.tap() }
            sleep(1)
            let after = app.buttons.matching(labelContains("milligrams of caffeine")).firstMatch.label
            check(after != before, "caffeine label changed after adding coffee (\(before) -> \(after))")
        }
        step("Active Stacks tile opens Stacks tab") {
            let t = text("Active Stacks")
            scrollTo(t)
            if waitFor(t, 5, "Active Stacks tile") { t.tap() }
            waitFor(navBar("Stacks"), 5, "Stacks tab after tile tap")
        }
        goHome()
        step("Running Low tile popout") {
            let t = text("Running Low")
            scrollTo(t)
            if waitFor(t, 5, "Running Low tile") { t.tap() }
            waitFor(navBar("Supply"), 5, "Supply sheet")
            let refill = button("Refill")
            if tapIf(refill) {
                check(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Refill'")).firstMatch.waitForExistence(timeout: 3), "Refill sheet from Supply")
                snap("refill from supply")
                closeSheet()
            }
        }
        closeSheet()
        step("This Week tile opens week overview") {
            let t = text("This Week")
            scrollTo(t)
            if waitFor(t, 5, "This Week tile") { t.tap() }
            sleep(2)
            check(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS ' to '")).firstMatch.waitForExistence(timeout: 3), "week overview sheet after This Week tap")
        }
        closeSheet()
        goHome()
        step("Coming Up tile popout") {
            let t = text("Coming Up")
            scrollTo(t)
            if waitFor(t, 5, "Coming Up tile") { t.tap() }
            waitFor(navBar("Coming Up"), 5, "Coming Up sheet")
        }
        closeSheet()
        step("Recent tile opens Dose Log") {
            let t = text("Recent")
            scrollTo(t)
            if waitFor(t, 5, "Recent tile") { t.tap() }
            waitFor(navBar("Dose Log"), 5, "Dose Log after Recent tap")
        }
        goBack()
        step("Discreet tile toggles") {
            let eye = app.images.matching(labelBegins("Discreet Mode")).firstMatch
            scrollTo(eye)
            if waitFor(eye, 5, "Discreet tile eye") {
                let before = eye.label
                eye.tap()
                sleep(1)
                check(eye.label != before, "Discreet tile label changed (\(before) to \(eye.label))")
                snap("discreet on")
                eye.tap()
                sleep(1)
                check(eye.label == before, "Discreet tile back to \(before)")
            }
        }
    }

    func test03_EditHome() {
        launch()
        step("Edit Home sheet") {
            button("Edit").tap()
            waitFor(navBar("Edit Home"), 5, "Edit Home sheet")
        }
        step("Hide first card and resize") {
            let s = app.switches.firstMatch
            if s.exists { s.tap() }
            let large = app.buttons["Large"].firstMatch
            if large.exists { large.tap() }
        }
        step("Save layout") {
            button("Done").tap()
            sleep(1)
        }
        step("Reset layout") {
            button("Edit").tap()
            let reset = button("Reset to the Default Layout")
            scrollTo(reset)
            if waitFor(reset, 4, "Reset button") { reset.tap() }
            button("Done").tap()
        }
    }

    func test04_UpNextLogAndRecentEditDelete() {
        launch()
        step("Up Next Log button") {
            let b = app.buttons.matching(NSPredicate(format: "label == 'Log' OR label == 'Log All'")).firstMatch
            if waitFor(b, 5, "Up Next Log button") { b.tap() }
            check(app.navigationBars.matching(NSPredicate(format: "identifier == 'Log Dose' OR identifier == 'Log Doses'")).count > 0
                  || navBar("Log Dose").exists || navBar("Log Doses").exists, "log sheet from Up Next")
        }
        closeSheet()
        step("Recent long press, Edit Dose") {
            let header = text("Recent")
            scrollTo(header)
            let row = app.staticTexts.allElementsBoundByIndex.first { $0.frame.minY > header.frame.maxY + 4 && ["Adderall", "Caffeine", "Escitalopram", "Vitamin D3", "Fish Oil", "L-Theanine", "NAC"].contains($0.label) }
            if let row {
                row.press(forDuration: 1.0)
                let edit = button("Edit Dose")
                if waitFor(edit, 3, "Edit Dose in Recent menu") { edit.tap() }
                waitFor(navBar("Edit Dose"), 4, "Edit Dose sheet")
                closeSheet()
                row.press(forDuration: 1.0)
                let del = button("Delete Dose")
                if waitFor(del, 3, "Delete Dose in Recent menu") { del.tap() }
                let undo = button("Undo")
                if waitFor(undo, 4, "Undo toast after delete") {
                    check(app.staticTexts.matching(labelBegins("Deleted")).count > 0, "Deleted toast text")
                    snap("deleted toast")
                    undo.tap()
                }
            } else {
                check(false, "a Recent row")
            }
        }
    }
}

final class B2_ReproTests: MedJarsUITestCase {
    private func openAll(_ label: String) -> Bool {
        tapPlus()
        _ = plusMenuLog()
        let all = button("All")
        guard all.waitForExistence(timeout: 3) else { check(false, "All button (\(label))"); return false }
        all.tap()
        let ok = navBar("Log a Substance").waitForExistence(timeout: 4)
        snap("all sheet \(label) shown=\(ok)")
        mark("REPRO all-sheet \(label) shown=\(ok)")
        check(ok, "All sheet opens (\(label))")
        if ok { closeSheet() }
        return ok
    }

    func test01_AllSheetRepeated() {
        launch()
        for i in 1...4 { step("All sheet attempt \(i)") { _ = openAll("fresh \(i)") } }
        step("Log Next then All") {
            tapPlus()
            _ = plusMenuLog()
            if tapIf(button("Log Next")) { sleep(1); closeSheet() }
            _ = openAll("after Log Next")
        }
        step("Plan sheet then All") {
            tapPlus()
            if tapIf(button("Schedule")) { sleep(1); closeSheet() }
            _ = openAll("after Plan")
        }
    }

    func test02_ThisWeekFreshLaunch() {
        launch()
        step("This Week before Schedule was ever opened") {
            let t = text("This Week")
            scrollTo(t)
            if waitFor(t, 5, "This Week tile") { t.tap() }
            let ok = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS ' to '")).firstMatch.waitForExistence(timeout: 4)
            mark("REPRO thisweek-fresh shown=\(ok)")
            check(ok, "week overview from This Week on a fresh launch")
            closeSheet()
        }
        step("Week at a Glance button afterwards") {
            let b = button("Week at a Glance")
            if waitFor(b, 4, "calendar button") { b.tap() }
            let ok = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS ' to '")).firstMatch.waitForExistence(timeout: 4)
            mark("REPRO weekglance-after shown=\(ok)")
            check(ok, "Week at a Glance still opens")
            closeSheet()
        }
        step("This Week again after visiting Schedule") {
            tab("Home")
            let t = text("This Week")
            scrollTo(t)
            if t.exists { t.tap() }
            let ok = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS ' to '")).firstMatch.waitForExistence(timeout: 4)
            mark("REPRO thisweek-second shown=\(ok)")
            check(ok, "week overview from This Week a second time")
            closeSheet()
        }
    }

    func test03_PlusSuggestionWithMissedDose() {
        launch()
        tab("Cabinet")
        step("Plus on a page with a missed dose earlier today") {
            let t = app.cells.staticTexts["Magnesium Glycinate"].firstMatch
            scrollTo(t)
            t.tap()
            _ = button("Edit").waitForExistence(timeout: 4)
            snap("magnesium page")
            pageLogButton()?.tap()
            sleep(1)
            snap("plus suggestion sheet")
            let early = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This dose isn't due")).firstMatch.exists
            mark("REPRO suggestion early-warning=\(early)")
            check(!early, "plus offers the missed dose, not a later one")
            closeSheet()
        }
    }

    func test04_PagesSkippedEarlier() {
        for id in ["ibuprofen", "zinc", "ashwagandha"] {
            launch(extra: ["-previewRoute", "jar:\(id)"])
            step("Page \(id) opened directly") {
                check(button("Edit").waitForExistence(timeout: 8), "page \(id) shows Edit")
                snap("\(id) top")
                app.swipeUp(velocity: .fast); usleep(700_000); snap("\(id) middle")
                app.swipeUp(velocity: .fast); app.swipeUp(velocity: .fast); usleep(700_000); snap("\(id) bottom")
            }
        }
    }

    func test05_CoffeeShowsRightAway() {
        launch()
        step("Coffee from the Caffeine tile shows right away") {
            let cup = app.buttons.matching(labelContains("milligrams of caffeine")).firstMatch
            scrollTo(cup)
            let before = cup.label
            if waitFor(cup, 5, "Caffeine tile button") { cup.tap() }
            let coffee = button("Coffee, 95 mg")
            if waitFor(coffee, 4, "Coffee preset in caffeine menu") { coffee.tap() }
            sleep(1)
            let after = app.buttons.matching(labelContains("milligrams of caffeine")).firstMatch.label
            mark("REPRO coffee before=\(before) after=\(after)")
            check(after != before, "caffeine label changed after adding coffee (\(before) -> \(after))")
        }
    }
}

final class B_PlusTests: MedJarsUITestCase {
    func test01_PlusMenus() {
        launch()
        step("Plus opens menu") {
            tapPlus()
            waitFor(button("Schedule"), 3, "plus menu Schedule")
        }
        step("Log then Log Next") {
            _ = plusMenuLog()
            let next = button("Log Next")
            if waitFor(next, 3, "Log Next") { next.tap() }
            sleep(1)
            check(navBar("Log Dose").exists || navBar("Log Next").exists || app.alerts.count > 0, "Log Next opened a sheet")
        }
        closeSheet()
        step("All substances, log two") {
            tapPlus()
            _ = plusMenuLog()
            if tapIf(button("All")) {
                waitFor(navBar("Log a Substance"), 4, "All sheet")
                _ = tapIf(button("Select Fish Oil"))
                _ = tapIf(button("Select Vitamin D3"))
                let go = button("Log 2 Selected")
                if waitFor(go, 3, "Log 2 Selected") { go.tap() }
                let logIt = app.buttons.matching(labelBegins("Log 2 Doses")).firstMatch
                if waitFor(logIt, 5, "group sheet Log 2 Doses") { logIt.tap() }
            }
        }
        step("Plan a dose from plus") {
            tapPlus()
            if tapIf(button("Schedule")) {
                waitFor(navBar("Plan a Dose"), 4, "Plan a Dose sheet")
                let save = button("Save")
                if save.exists { save.tap() }
            }
        }
        step("Plus menu closes from the dim area") {
            tapPlus()
            let dim = app.descendants(matching: .any)["Close menu"].firstMatch
            if waitFor(dim, 3, "dim layer") { dim.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap() }
            sleep(1)
            check(!app.descendants(matching: .any)["Close menu"].exists, "menu closed")
        }
        step("Hold plus to scan") {
            let plus = button("Log or Schedule")
            plus.press(forDuration: 0.8)
            sleep(2)
            snap("scan attempt")
            if app.alerts.firstMatch.exists { app.alerts.buttons.firstMatch.tap() }
        }
    }

    func test02_PlusOnSubstancePage() {
        launch()
        tab("Cabinet")
        step("Open Magnesium") {
            let t = text("Magnesium Glycinate")
            scrollTo(t)
            t.tap()
            waitFor(button("Edit"), 5, "substance page")
            check(!app.buttons["Log or Schedule"].exists, "no plus button on a substance page, its Log bar logs it")
        }
        step("Log bar logs Magnesium") {
            if let log = pageLogButton() { log.tap() } else { check(false, "Log bar button") }
            waitFor(navBar("Log Dose"), 4, "log sheet for Magnesium")
            snap("page log sheet")
            check(!app.staticTexts.matching(labelBegins("This dose isn't due")).firstMatch.exists, "offers the missed dose, not a later one")
            tapLogSheetButton()
            waitFor(button("Undo"), 5, "undo toast on substance page")
        }
    }
}

final class C_LoggingTests: MedJarsUITestCase {
    func test01_LogEditDeleteUndoSkip() {
        launch()
        tab("Schedule")
        let listLog = app.collectionViews.buttons.matching(label("Log"))
        step("Log a dose from Schedule") {
            let log = listLog.firstMatch
            scrollTo(log)
            if waitFor(log, 5, "a Log button in the Schedule list") { log.tap() }
            waitFor(navBar("Log Dose"), 4, "log sheet")
            let amount = app.descendants(matching: .any)["Amount"].firstMatch
            if amount.exists { amount.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
            snap("log sheet bumped")
            tapLogSheetButton()
            let undo = button("Undo")
            if waitFor(undo, 5, "Logged toast") { snap("logged toast"); undo.tap() }
        }
        step("Log then edit to 0 deletes") {
            let log = listLog.firstMatch
            scrollTo(log)
            if waitFor(log, 5, "Log button again") { log.tap() }
            _ = navBar("Log Dose").waitForExistence(timeout: 4)
            tapLogSheetButton()
            sleep(1)
            let taken = app.collectionViews.staticTexts.matching(labelBegins("Taken")).firstMatch
            scrollTo(taken)
            if waitFor(taken, 5, "a Taken row") { taken.tap() }
            if waitFor(navBar("Edit Dose"), 4, "Edit Dose sheet") {
                let amount = app.descendants(matching: .any)["Amount"].firstMatch
                for _ in 0..<6 where amount.exists { amount.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap() }
                snap("edit at zero")
                let del = app.buttons.matching(label("Delete Dose")).allElementsBoundByIndex.filter { $0.isHittable }.max { $0.frame.maxY < $1.frame.maxY }
                check(del != nil, "Delete Dose button when amount is 0")
                del?.tap()
                let undo = button("Undo")
                if waitFor(undo, 5, "Deleted toast after 0") { snap("deleted toast"); undo.tap() }
            }
        }
        step("Delete Dose button at the bottom of edit") {
            let taken = app.collectionViews.staticTexts.matching(labelBegins("Taken")).firstMatch
            scrollTo(taken)
            if waitFor(taken, 5, "a Taken row for delete") { taken.tap() }
            if navBar("Edit Dose").waitForExistence(timeout: 4) {
                for _ in 0..<3 { app.swipeUp(velocity: .slow) }
                let del = app.collectionViews.buttons["Delete Dose"].firstMatch
                if waitFor(del, 4, "Delete Dose row") { del.tap() }
                let undo = button("Undo")
                if waitFor(undo, 5, "Deleted toast") { undo.tap() }
            }
        }
        step("Skip a dose and undo the skip") {
            let open = listLog.firstMatch
            scrollTo(open)
            if waitFor(open, 4, "an open dose") {
                open.swipeLeft()
                if tapIf(button("Skip")) {
                    let skip = button("Skip Dose")
                    if waitFor(skip, 4, "Skip sheet") { skip.tap() }
                    let skipped = app.collectionViews.staticTexts.matching(labelBegins("Skipped")).firstMatch
                    scrollTo(skipped)
                    if waitFor(skipped, 4, "Skipped row") {
                        skipped.tap()
                        let undo = button("Undo Skip")
                        if waitFor(undo, 4, "Undo Skip") { undo.tap() }
                    }
                } else { check(false, "Skip swipe action") }
            }
        }
        step("Log All on a group") {
            let all = app.collectionViews.buttons.matching(label("Log All")).firstMatch
            scrollTo(all)
            if all.waitForExistence(timeout: 3) {
                all.tap()
                waitFor(app.buttons.matching(labelBegins("Log ")).matching(labelContains("Doses")).firstMatch, 4, "group sheet")
                snap("group sheet")
                closeSheet()
            } else {
                mark("NOTE no Log All group visible today")
            }
        }
    }

    func test02_SeveralJarsLogSheet() {
        launch()
        tab("Cabinet")
        step("Adderall page") {
            let t = text("Adderall")
            scrollTo(t)
            t.tap()
            waitFor(button("Edit"), 5, "Adderall page")
        }
        step("Adderall log sheet shows each jar") {
            button("Log Adderall").tap()
            waitFor(navBar("Log Dose"), 4, "Adderall log sheet")
            check(app.staticTexts.matching(labelContains("10 mg")).count > 0, "10 mg jar row in log sheet")
            check(text("Total").exists, "Total row")
        }
        closeSheet()
    }

    func test03_DoseLogHistory() {
        launch()
        tab("Cabinet")
        step("Open Dose Log") {
            button("Dose Log").tap()
            waitFor(navBar("Dose Log"), 5, "Dose Log")
        }
        step("Swipe delete and undo in Dose Log") {
            let cell = app.cells.firstMatch
            if waitFor(cell, 4, "a dose cell") {
                cell.swipeLeft()
                if tapIf(button("Delete")) {
                    let undo = button("Undo")
                    if waitFor(undo, 4, "Undo after Dose Log delete") { undo.tap() }
                }
            }
        }
        step("Check-in from Dose Log") {
            let cell = app.cells.element(boundBy: 1)
            if cell.exists {
                cell.swipeRight()
                if tapIf(button("Check In")) {
                    waitFor(navBar("How Are You Feeling?"), 4, "check-in sheet")
                    _ = tapIf(button("4 of 5"))
                    snap("check-in")
                    _ = tapIf(button("Save"))
                }
            }
        }
        step("Fast scroll the Dose Log") {
            for _ in 0..<10 { app.swipeUp(velocity: .fast) }
            for _ in 0..<10 { app.swipeDown(velocity: .fast) }
        }
        responsive("Dose Log scroll")
    }
}

final class D_ScheduleTests: MedJarsUITestCase {
    func test01_WeekStripAndDays() {
        launch()
        tab("Schedule")
        let days = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), .*"))
        step("Week strip has 7 days") { check(days.count >= 7, "7 day buttons (found \(days.count))") }
        for i in 0..<7 {
            step("Schedule day \(i + 1)") {
                let d = days.element(boundBy: i)
                if d.exists { d.tap() }
                usleep(600_000)
            }
        }
        step("Swipe the strip to next and previous week") {
            let first = days.element(boundBy: 0)
            first.swipeLeft()
            sleep(1)
            snap("next week")
            first.swipeRight()
            first.swipeRight()
            sleep(1)
        }
        step("Today button") {
            _ = tapIf(button("Today"))
        }
        step("Scrolled list keeps a frosted strip") {
            app.swipeUp(velocity: .slow)
            app.swipeUp(velocity: .slow)
        }
        scrollToTop()
        step("Week at a Glance") {
            button("Week at a Glance").tap()
            sleep(1)
            check(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS ' to '")).firstMatch.waitForExistence(timeout: 3), "week overview")
            _ = tapIf(button("Next Week"))
            snap("next week overview")
            _ = tapIf(button("Previous Week"))
            closeSheet()
        }
    }

    func test02_RowActions() {
        launch()
        tab("Schedule")
        step("Bedtime row sheet") {
            let bed = app.descendants(matching: .any).matching(labelBegins("Bedtime")).firstMatch
            if waitFor(bed, 4, "Bedtime row") { bed.tap() }
            sleep(1)
            snap("bedtime sheet")
            // Move the time an hour so it counts as a change.
            let picker = app.datePickers.firstMatch
            var changed = false
            if picker.exists {
                picker.tap()
                let wheel = app.pickerWheels.firstMatch
                if wheel.waitForExistence(timeout: 2) {
                    let current = wheel.value as? String ?? ""
                    wheel.adjust(toPickerWheelValue: current.hasPrefix("10") ? "9" : "10")
                    changed = true
                }
                app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            _ = tapIf(button("Save"))
            sleep(1)
            if changed {
                check(app.staticTexts["Changed for this day"].waitForExistence(timeout: 3), "bedtime shows changed")
            } else {
                mark("NOTE bedtime time picker not reachable, change not checked")
            }
            if bed.exists { bed.tap() }
            if tapIf(button("Go Back to the Regular Bedtime")) == false { closeSheet() }
        }
        step("Edit Day from a swipe") {
            let name = app.staticTexts["Fish Oil"].firstMatch
            scrollTo(name)
            if waitFor(name, 4, "Fish Oil row") {
                name.swipeRight()
                if tapIf(button("Edit Day")) {
                    waitFor(navBar("Edit This Day"), 4, "Edit This Day sheet")
                    closeSheet()
                }
            }
        }
        step("Long press, Open substance") {
            scrollToTop()
            let name = app.staticTexts["Vitamin D3"].firstMatch
            scrollTo(name)
            if waitFor(name, 4, "Vitamin D3 row") {
                name.press(forDuration: 1.0)
                if tapIf(button("Open Vitamin D3")) {
                    waitFor(button("Edit"), 4, "Vitamin D3 page from Schedule")
                    goBack()
                }
            }
        }
        step("Planned dose on its day") {
            let days = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), .*"))
            let todayIndex = (0..<days.count).first { days.element(boundBy: $0).label.contains("today") } ?? 0
            if todayIndex + 1 < days.count { days.element(boundBy: todayIndex + 1).tap() }
            sleep(1)
            let exam = app.staticTexts.matching(labelContains("Exam")).firstMatch
            scrollTo(exam)
            check(exam.exists, "planned dose shows tomorrow")
        }
    }
}

final class E_CabinetTests: MedJarsUITestCase {
    let names = ["Adderall", "Escitalopram", "Vitamin D3", "Magnesium Glycinate", "Fish Oil", "Creatine", "L-Theanine", "Caffeine",
                 "Melatonin", "Ibuprofen", "Zinc", "Ashwagandha", "NAC", "Cannabis", "Vitamin B12", "Iron"]

    func test01_EverySubstancePage() {
        launch()
        tab("Cabinet")
        step("Cabinet list") { waitFor(navBar("Cabinet"), 5, "Cabinet") }
        for n in names {
            step("Page \(n)") {
                let t = app.cells.staticTexts[n].firstMatch
                scrollTo(t)
                if !waitFor(t, 3, "Cabinet row \(n)") { return }
                let start = Date()
                t.tap()
                let ok = button("Edit").waitForExistence(timeout: 8)
                mark(String(format: "PAGE %@ %.0fms", n, Date().timeIntervalSince(start) * 1000))
                check(ok, "page for \(n)")
                for i in 0..<3 { app.swipeUp(velocity: .default); if i == 1 { snap("\(n) middle") } }
                snap("\(n) bottom")
                goBack()
                usleep(500_000)
            }
        }
    }

    func test02_SubstancePageActions() {
        launch()
        tab("Cabinet")
        let t = text("Magnesium Glycinate")
        t.tap()
        step("Pause and resume") {
            button("More").tap()
            if tapIf(button("Pause Jar")) {
                check(app.staticTexts.matching(labelBegins("Paused")).count > 0, "paused banner")
                button("More").tap()
                _ = tapIf(button("Resume Jar"))
            }
        }
        step("Schedule a break") {
            button("More").tap()
            if tapIf(button("Schedule a Break")) {
                waitFor(navBar("Take a Break"), 4, "break sheet")
                _ = tapIf(button("Save"))
                sleep(1)
                snap("break set")
                let remove = button("Remove Break")
                if remove.exists { remove.tap() } else {
                    button("More").tap(); _ = tapIf(button("Edit Break"))
                    if tapIf(button("Remove Break")) == false { closeSheet() }
                }
            }
        }
        step("Log an extra dose sheet") {
            button("More").tap()
            if tapIf(button("Log an Extra Dose")) {
                waitFor(navBar("Log Dose"), 4, "extra dose sheet")
                closeSheet()
            }
        }
        step("Plan a dose sheet") {
            button("More").tap()
            if tapIf(button("Plan a Dose")) {
                waitFor(navBar("Plan a Dose"), 4, "plan sheet")
                closeSheet()
            }
        }
        step("Recent Doses swipe delete and undo") {
            let show = button("Show All Doses")
            scrollTo(show)
            let cells = app.cells.allElementsBoundByIndex.filter { $0.frame.maxY < show.frame.minY && $0.frame.minY > 0 }
            if let last = cells.last {
                last.swipeLeft()
                if tapIf(button("Delete")) {
                    let undo = button("Undo")
                    if waitFor(undo, 4, "undo after Recent Doses delete") { undo.tap() }
                }
            } else { check(false, "recent dose cells") }
        }
        step("Refill or Recount") {
            let refill = button("Refill or Recount")
            scrollTo(refill, up: false)
            scrollTo(refill)
            if tapIf(refill) {
                let field = app.textFields.firstMatch
                if field.waitForExistence(timeout: 3) { field.tap(); field.typeText("10") }
                _ = tapIf(button("Save"))
            }
        }
        step("Editor opens and scrolls") {
            scrollToTop()
            button("Edit").tap()
            waitFor(navBar("Edit Substance"), 4, "editor")
            for _ in 0..<8 { app.swipeUp(velocity: .fast) }
            snap("editor bottom")
            closeSheet()
        }
    }
}

final class F_EditorTests: MedJarsUITestCase {
    func openNew() {
        tab("Cabinet")
        button("Add Substance").tap()
        waitFor(app.textFields["Medication or Supplement"], 5, "editor open")
    }

    func typeIn(_ s: String, _ field: XCUIElement) {
        scrollTo(field)
        field.tap()
        field.typeText(s)
    }

    func save() {
        app.navigationBars.buttons["Save"].firstMatch.tap()
        sleep(1)
    }

    func test01_CreateSimple() {
        launch()
        step("New simple substance") {
            openNew()
            typeIn("Test Vitamin C", app.textFields["Medication or Supplement"])
            typeIn("500", app.textFields["e.g. 30"].firstMatch)
            let done = app.toolbars.buttons["Done"].firstMatch
            check(done.waitForExistence(timeout: 3), "keyboard Done bar on a number field")
            snap("keyboard bar")
            if done.exists { done.tap() }
            save()
            check(app.cells.staticTexts["Test Vitamin C"].waitForExistence(timeout: 4), "Test Vitamin C in Cabinet")
        }
        step("Open new substance") {
            app.cells.staticTexts["Test Vitamin C"].firstMatch.tap()
            waitFor(button("Edit"), 4, "new page")
            check(!app.staticTexts["Missed"].exists, "a substance added today shows no missed dose")
        }
        step("Delete it from the editor") {
            button("Edit").tap()
            let del = button("Delete Substance")
            scrollTo(del)
            if tapIf(del) {
                let confirm = app.buttons.matching(label("Delete Substance")).allElementsBoundByIndex.last
                confirm?.tap()
            }
            sleep(1)
            check(!app.cells.staticTexts["Test Vitamin C"].exists, "deleted from Cabinet")
        }
    }

    func test02_AsNeededWithLimits() {
        launch()
        step("New as-needed with a minimum gap") {
            openNew()
            typeIn("Test Aspirin", app.textFields["Medication or Supplement"])
            typeIn("81", app.textFields["e.g. 30"].firstMatch)
            let prn = app.switches["As Needed"]
            scrollTo(prn)
            prn.switches.firstMatch.exists ? prn.switches.firstMatch.tap() : prn.tap()
            let gap = app.buttons.matching(labelBegins("Minimum Gap")).firstMatch
            scrollTo(gap)
            if tapIf(gap) {
                snap("gap picker")
                _ = tapIf(button("4 hr")) || tapIf(button("4 hours")) || tapIf(app.buttons.matching(labelBegins("4 hr")).firstMatch)
            }
            snap("as-needed editor")
            save()
        }
        step("Log twice, gap warning") {
            let row = app.cells.staticTexts["Test Aspirin"].firstMatch
            scrollTo(row)
            row.tap()
            _ = button("Edit").waitForExistence(timeout: 4)
            if let plus = pageLogButton() {
                plus.tap()
                _ = navBar("Log Dose").waitForExistence(timeout: 4)
                tapLogSheetButton()
                sleep(2)
                pageLogButton()?.tap()
                _ = navBar("Log Dose").waitForExistence(timeout: 4)
                check(app.buttons["Log Anyway"].waitForExistence(timeout: 3), "Log Anyway after minimum gap")
                snap("gap warning")
                closeSheet()
            }
        }
    }

    func test03_SeveralJarsAndAdvanced() {
        launch()
        step("New substance with two jars") {
            openNew()
            typeIn("Test Multi", app.textFields["Medication or Supplement"])
            typeIn("10", app.textFields["e.g. 30"].firstMatch)
            let add = app.buttons.matching(labelBegins("Add Another Jar")).firstMatch
            scrollTo(add)
            if tapIf(add) {
                let f = app.textFields["e.g. 30"].firstMatch
                if f.waitForExistence(timeout: 3) { f.tap(); f.typeText("20") }
                snap("second jar editor")
                goBack()
            }
            snap("two jars editor")
            save()
            check(app.cells.staticTexts["Test Multi"].waitForExistence(timeout: 4), "Test Multi saved")
        }
        step("New substance with an advanced schedule") {
            openNew()
            typeIn("Test Rule", app.textFields["Medication or Supplement"])
            typeIn("5", app.textFields["e.g. 30"].firstMatch)
            let adv = app.switches["Advanced Schedule"]
            scrollTo(adv)
            if adv.exists { adv.switches.firstMatch.exists ? adv.switches.firstMatch.tap() : adv.tap() }
            let repeats = app.buttons.matching(labelBegins("Repeats")).firstMatch
            scrollTo(repeats)
            if tapIf(repeats) { _ = tapIf(button("Every Few Days")) }
            snap("advanced editor")
            save()
        }
        step("New capsule with imprint side and effect timeline") {
            openNew()
            typeIn("Test Effect", app.textFields["Medication or Supplement"])
            let form = app.buttons.matching(labelBegins("Form")).firstMatch
            if tapIf(form) { _ = tapIf(button("Capsule")) }
            typeIn("15", app.textFields["e.g. 30"].firstMatch)
            let imprint = app.textFields["e.g. dp 10"].firstMatch
            scrollTo(imprint)
            if imprint.exists { imprint.tap(); imprint.typeText("AB 12") }
            let split = button("Split")
            check(split.waitForExistence(timeout: 3), "Imprint Side picker shows for a capsule")
            if split.exists { split.tap() }
            snap("imprint split")
            let effect = app.switches["Effect Timeline and Duration"]
            scrollTo(effect)
            if effect.exists { effect.switches.firstMatch.exists ? effect.switches.firstMatch.tap() : effect.tap() }
            snap("effect on")
            save()
        }
        step("Log it and see Working Now") {
            let row = app.cells.staticTexts["Test Effect"].firstMatch
            scrollTo(row)
            row.tap()
            _ = button("Edit").waitForExistence(timeout: 4)
            if let plus = pageLogButton() {
                plus.tap()
                _ = navBar("Log Dose").waitForExistence(timeout: 4)
                snap("test effect log sheet")
                tapLogSheetButton()
                sleep(1)
            } else {
                check(false, "Log bar on Test Effect")
            }
            check(app.staticTexts["Peaks in"].waitForExistence(timeout: 4), "effect timeline live on the page")
            snap("test effect page live")
            goHome()
            let t = text("Working Now")
            scrollTo(t)
            check(app.staticTexts.matching(labelBegins("Test Effect")).firstMatch.waitForExistence(timeout: 3), "Test Effect in Working Now")
        }
    }
}

final class G_StackTests: MedJarsUITestCase {
    func test01_StackFlows() {
        launch()
        tab("Stacks")
        step("Stacks list") { waitFor(navBar("Stacks"), 4, "Stacks") }
        step("Focus detail and views") {
            let f = app.staticTexts["Focus"].firstMatch
            if waitFor(f, 4, "Focus row") { f.tap() }
            sleep(1)
            for v in ["Week", "Month", "Day"] {
                _ = tapIf(button(v))
                snap("focus \(v)")
            }
            _ = tapIf(button("Next Day"))
            _ = tapIf(button("Previous Day"))
        }
        step("Focus length menu") {
            let len = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Until' OR label CONTAINS 'Runs' OR label CONTAINS 'Ends' OR label CONTAINS 'Length'")).firstMatch
            if len.exists { len.tap(); snap("length menu"); app.tap() }
        }
        goBack()
        step("Turn on Sleep") {
            let s = app.staticTexts["Sleep"].firstMatch
            if waitFor(s, 4, "Sleep row") { s.tap() }
            let on = app.switches.firstMatch
            if waitFor(on, 4, "On switch") { on.tap() }
            if tapIf(button("Turn On"), 4) { sleep(1) }
            snap("sleep on")
            if on.exists { on.tap() }
            _ = tapIf(button("Turn Off"))
        }
        goBack()
        step("New stack") {
            button("New Stack").tap()
            let name = app.textFields["Name, e.g. Focus"].firstMatch
            if waitFor(name, 4, "stack name field") { name.tap(); name.typeText("Test Stack") }
            let add = button("Add a Substance")
            scrollTo(add)
            if tapIf(add) { _ = tapIf(button("Zinc")) }
            snap("new stack")
            _ = tapIf(app.navigationBars.buttons["Save"].firstMatch)
            check(app.staticTexts["Test Stack"].waitForExistence(timeout: 4), "Test Stack saved")
        }
        step("Delete the new stack") {
            app.staticTexts["Test Stack"].firstMatch.tap()
            if tapIf(button("Edit")) {
                let del = button("Delete Stack")
                scrollTo(del)
                if tapIf(del) { app.buttons.matching(label("Delete Stack")).allElementsBoundByIndex.last?.tap() }
            }
        }
    }
}

final class H_SettingsTests: MedJarsUITestCase {
    func test01_Settings() {
        launch()
        step("Open Settings") {
            button("Settings").tap()
            waitFor(app.switches.matching(labelContains("Face ID")).firstMatch, 5, "Settings")
        }
        for i in 1...5 { step("Settings scrolled \(i)") { app.swipeUp(velocity: .slow) } }
        scrollToTop()
        step("Theme preset") {
            let theme = app.buttons.matching(labelBegins("Theme")).firstMatch
            if tapIf(theme) {
                _ = tapIf(button("Blue"))
                snap("theme blue")
                _ = tapIf(button("Orange"))
                goBack()
            }
        }
        step("Discreet Mode on a schedule") {
            let picker = app.buttons.matching(labelBegins("Discreet Mode")).firstMatch
            if tapIf(picker) {
                _ = tapIf(button("On a Schedule"))
                sleep(1)
                snap("discreet scheduled")
                if tapIf(picker) { _ = tapIf(button("Off")) }
            }
        }
        step("Group reminders toggle") {
            let s = app.switches.matching(labelContains("Group Same-Time")).firstMatch
            scrollTo(s)
            if s.exists { s.tap(); usleep(500_000); s.tap() }
        }
        step("Different bedtimes on some days") {
            let d = button("Different on Some Days")
            scrollTo(d)
            if tapIf(d) { snap("weekday bedtimes") }
        }
        step("Caffeine tracker off and on") {
            let s = app.switches.matching(labelContains("Caffeine Tracker")).firstMatch
            scrollTo(s)
            if s.exists { s.tap(); usleep(500_000); s.tap() }
        }
        step("Import a jar") {
            let field = app.textFields["Paste jar text here"].firstMatch
            let tv = app.textViews.firstMatch
            let target = field.exists ? field : tv
            scrollTo(target)
            if target.exists {
                target.tap()
                target.typeText(#"{"id":"test-import","name":"Test Import","kind":"supplement","bottles":[{"id":"test-import","form":"tablet","strength":5,"unit":"mg"}],"defaultBottleId":"test-import","plans":[{"days":[1,2,3,4,5,6,7],"dailyPills":1,"doses":[{"time":"09:00","pills":1,"share":1}]}]}"#)
                let doneKey = app.toolbars.buttons["Done"].firstMatch
                if doneKey.exists { doneKey.tap() }
                let imp = button("Import")
                scrollTo(imp)
                _ = tapIf(imp)
                check(app.staticTexts.matching(labelBegins("Imported 1 new")).firstMatch.waitForExistence(timeout: 3), "import result")
            }
        }
        step("NFC instructions") {
            let n = button("Open Jars from the Lock Screen")
            scrollTo(n)
            _ = tapIf(n)
        }
        step("Export backup share sheet") {
            let e = button("Export Backup")
            scrollTo(e, up: false)
            if tapIf(e) { sleep(2); snap("share sheet"); app.swipeDown(velocity: .fast); closeSheet() }
        }
    }

    func test02_CaffeinePage() {
        launch()
        tab("Cabinet")
        step("Caffeine page") {
            let c = app.staticTexts.matching(labelContains("mg in your system")).firstMatch
            if waitFor(c, 4, "Cabinet caffeine row") { c.tap() }
            sleep(1)
        }
        step("Custom caffeine") {
            let add = app.buttons["Add caffeine"].firstMatch
            if tapIf(add) {
                if tapIf(button("Custom Amount")) {
                    let f = app.textFields["e.g. 150"].firstMatch
                    if f.waitForExistence(timeout: 3) { f.tap(); f.typeText("120") }
                    _ = tapIf(button("Add"))
                }
            }
        }
    }
}

// MARK: - Stress and performance

final class X_StressTests: MedJarsUITestCase {
    func test01_FastScrollingAndRapidActions() {
        launch()
        step("Home fast scroll x25", snapAfter: false) {
            for _ in 0..<25 { app.swipeUp(velocity: .fast); app.swipeDown(velocity: .fast) }
        }
        snap("after home fast scroll")
        responsive("home fast scroll")
        step("Tab switching x40", snapAfter: false) {
            let tabs = ["Cabinet", "Schedule", "Stacks", "Home"]
            for i in 0..<40 { app.tabBars.buttons[tabs[i % 4]].tap() }
        }
        responsive("tab switching")
        tab("Schedule")
        step("Week strip hopping x28", snapAfter: false) {
            let days = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), .*"))
            for i in 0..<28 { let d = days.element(boundBy: i % 7); if d.exists { d.tap() } }
        }
        step("Schedule fast scroll x15", snapAfter: false) {
            for _ in 0..<15 { app.swipeUp(velocity: .fast); app.swipeDown(velocity: .fast) }
        }
        snap("after schedule stress")
        responsive("schedule stress")
        tab("Cabinet")
        step("Open and close substance pages x15", snapAfter: false) {
            let rows = ["Adderall", "Escitalopram", "Vitamin D3", "Magnesium Glycinate", "Fish Oil"]
            for i in 0..<15 {
                let t = app.cells.staticTexts[rows[i % rows.count]].firstMatch
                if t.waitForExistence(timeout: 3) { t.tap() }
                _ = button("Edit").waitForExistence(timeout: 4)
                goBack()
            }
        }
        snap("after page stress")
        responsive("page push pop")
        step("Plus menu open and close x20", snapAfter: false) {
            for _ in 0..<20 {
                let plus = button("Log or Schedule")
                if plus.exists { plus.tap() }
                let close = button("Close")
                if close.waitForExistence(timeout: 2) { close.tap() }
            }
        }
        snap("after plus stress")
        check(!app.descendants(matching: .any)["Close menu"].exists, "plus dim layer gone after open/close")
        responsive("plus menu stress")
        step("Sheet open and close x12", snapAfter: false) {
            for _ in 0..<12 {
                let missed = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' Missed' OR label == 'Nothing missed'")).firstMatch
                if missed.waitForExistence(timeout: 3) { missed.tap() }
                let done = app.navigationBars.buttons["Done"].firstMatch
                if done.waitForExistence(timeout: 3) { done.tap() }
            }
        }
        snap("after sheet stress")
        step("A sheet still presents after stress") {
            let missed = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' Missed' OR label == 'Nothing missed'")).firstMatch
            if missed.waitForExistence(timeout: 3) { missed.tap() }
            check(navBar("Missed").waitForExistence(timeout: 4), "Missed sheet still opens after rapid open/close")
            closeSheet()
        }
        tab("Cabinet")
        step("Rapid log and undo x8 on a page", snapAfter: false) {
            let t = app.cells.staticTexts["Fish Oil"].firstMatch
            if t.waitForExistence(timeout: 3) { t.tap() }
            for _ in 0..<8 {
                let plus = button("Log Fish Oil")
                if plus.waitForExistence(timeout: 3) { plus.tap() }
                if navBar("Log Dose").waitForExistence(timeout: 3) { tapLogSheetButton() }
                let undo = button("Undo")
                if undo.waitForExistence(timeout: 3) { undo.tap() }
            }
        }
        snap("after log stress")
        responsive("rapid log undo")
        step("Background and foreground x6", snapAfter: false) {
            for _ in 0..<6 {
                XCUIDevice.shared.press(.home)
                sleep(1)
                app.activate()
                _ = app.tabBars.firstMatch.waitForExistence(timeout: 10)
            }
        }
        snap("after background stress")
        responsive("background foreground")
        goHome()
        step("Idle on Home 30s", snapAfter: false) {
            mark("IDLE BEGIN")
            sleep(30)
            mark("IDLE END")
        }
        snap("after idle")
        responsive("idle")
        step("Idle on Schedule 20s", snapAfter: false) {
            tab("Schedule")
            mark("IDLE2 BEGIN")
            sleep(20)
            mark("IDLE2 END")
        }
    }
}

final class Y_ScrollMetricTests: MedJarsUITestCase {
    private func measureScroll(_ title: String) {
        let opts = XCTMeasureOptions()
        opts.invocationOptions = [.manuallyStop]
        opts.iterationCount = 4
        mark("METRIC BEGIN \(title)")
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: opts) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
        mark("METRIC END \(title)")
    }

    func test01_HomeScroll() { launch(); measureScroll("Home") }
    func test02_ScheduleScroll() { launch(); tab("Schedule"); measureScroll("Schedule") }
    func test03_CabinetScroll() { launch(); tab("Cabinet"); measureScroll("Cabinet") }
    func test04_PageScroll() {
        launch(); tab("Cabinet")
        app.cells.staticTexts["Adderall"].firstMatch.tap()
        _ = app.buttons["Edit"].waitForExistence(timeout: 5)
        measureScroll("Adderall page")
    }
    func test05_LaunchTime() {
        launch()
        app.terminate()
        let opts = XCTMeasureOptions()
        opts.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: opts) {
            app.launchArguments = ["-perfHarness", "-askedForNotifications", "YES"]
            app.launch()
        }
    }
}
