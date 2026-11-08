import XCTest

final class CadenceWatchUITests:XCTestCase {
    override func setUpWithError()throws{continueAfterFailure=false}
    private func launch(largeText:Bool=false)->XCUIApplication{
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing"];if largeText{app.launchArguments.append("--watch-large-text")};app.launch();return app
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication,file:StaticString=#filePath,line:UInt=#line){
        for _ in 0..<6 where !element.isHittable{app.swipeUp()}
        XCTAssertTrue(element.isHittable,file:file,line:line)
    }
    private func capture(_ name:String){let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
    func testOfflinePlayerQueueAndSeek(){playerFlow()}
    func testLargeTextPlayerQueueAndSeek(){playerFlow(largeText:true)}
    private func playerFlow(largeText:Bool=false){
        let app=launch(largeText:largeText),play=app.buttons["watch.play"]
        XCTAssertTrue(play.waitForExistence(timeout:15));capture("Watch library")
        reveal(play,in:app);play.tap()
        let transport=app.buttons["watch.transport.play"];XCTAssertTrue(transport.waitForExistence(timeout:8));if largeText{reveal(transport,in:app)};XCTAssertTrue(transport.isHittable)
        capture("Watch now playing")
        let queue=app.buttons["watch.queue"];reveal(queue,in:app);queue.tap()
        XCTAssertTrue(app.staticTexts["Up next · 2"].waitForExistence(timeout:5));capture("Watch queue")
        let next=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","watch.queue.")).firstMatch
        XCTAssertTrue(next.isHittable);next.tap()
        XCTAssertTrue(transport.waitForExistence(timeout:5))
        let seek=app.buttons["watch.seek"];reveal(seek,in:app);seek.tap()
        let apply=app.buttons["watch.seek.apply"];XCTAssertTrue(app.descendants(matching:.any)["watch.seek.slider"].firstMatch.waitForExistence(timeout:5));capture("Watch seeking")
        reveal(apply,in:app);apply.tap();XCTAssertTrue(transport.waitForExistence(timeout:5))
        if transport.label=="Pause Watch"{transport.tap()}
    }
    func testDisconnectedMacOffersSavedWatchMusic(){
        let app=launch(),device=app.buttons["watch.device"].firstMatch
        XCTAssertTrue(device.waitForExistence(timeout:10));device.tap()
        let mac=app.buttons["watch.device.mac"];reveal(mac,in:app);mac.tap()
        let offline=app.buttons["watch.remote.offline"];XCTAssertTrue(offline.waitForExistence(timeout:8));reveal(offline,in:app)
        capture("Watch disconnected Mac");offline.tap()
        XCTAssertTrue(app.buttons["watch.play"].waitForExistence(timeout:5))
    }
    func testDevicePickerReturnsToSavedLibrary(){
        let app=launch(),device=app.buttons["watch.device"].firstMatch
        XCTAssertTrue(device.waitForExistence(timeout:10));device.tap()
        let phone=app.buttons["watch.device.phone"];XCTAssertTrue(phone.waitForExistence(timeout:5));capture("Watch device picker");phone.tap()
        XCTAssertTrue(app.buttons["watch.remote.reconnect"].waitForExistence(timeout:8));capture("Watch remote state")
        device.tap();let watch=app.buttons["watch.device.watch"];XCTAssertTrue(watch.waitForExistence(timeout:5));watch.tap()
        XCTAssertTrue(app.buttons["watch.play"].waitForExistence(timeout:5))
    }
}
