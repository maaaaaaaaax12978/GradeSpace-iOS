import XCTest

final class BallFlowTests: XCTestCase {
    @MainActor
    func testQuickTrialCommonThresholdAndWholeQuarterFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["quarter.1"].waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(app.buttons["quarter.1"].frame.height, 56)
        snapshot("01-subjects-large-quarter")

        app.tabBars.buttons["Призрачные"].tap()
        let stepper = app.steppers["trial.grade.5"]
        reveal(stepper, in: app)
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons.element(boundBy: 1).tap()
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(app.staticTexts["trial.average"].label, "4,75")
        let save = app.buttons["trial.save"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        snapshot("02-quick-trial")
        app.buttons["trial.reset"].tap()
        XCTAssertFalse(save.isEnabled)

        app.tabBars.buttons["Настройки"].tap()
        app.buttons["Изменить общий порог"].tap()
        let field = app.textFields["threshold.common"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["threshold.clear"].tap()
        field.tap()
        field.typeText("4,50")
        XCTAssertEqual(field.value as? String, "4,50")
        snapshot("03-common-threshold")
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["от 3,50"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Предметы"].tap()
        let review = app.buttons["quarter.review.all"]
        reveal(review, in: app, upwards: false)
        review.tap()
        XCTAssertTrue(app.navigationBars["I четверть"].waitForExistence(timeout: 5))
        snapshot("04-review-all-finals")
        let finish = app.buttons["quarter.finish.all"]
        reveal(finish, in: app)
        XCTAssertTrue(finish.isEnabled)
        finish.tap()
        XCTAssertTrue(app.staticTexts["Четверть завершена"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Завершено предметов: 2 из 2"].exists)
        snapshot("05-quarter-finished")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<7 {
            if element.isHittable { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
