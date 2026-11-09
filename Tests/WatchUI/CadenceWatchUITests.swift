import XCTest

final class CadenceWatchUITests:XCTestCase {
    override func setUpWithError()throws{continueAfterFailure=false;XCUIApplication().terminate()}
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
    func testAutomaticPhoneActivityDoesNotStopWatchPlayback(){
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--watch-lifecycle-fixture"];app.launch()
        let play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
        let transport=app.buttons["watch.transport.play"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Pause Watch"),object:transport)],timeout:8),.completed)
        app.buttons["watch.fixture.phone-event"].tap()
        XCTAssertEqual(app.buttons["watch.device"].firstMatch.label,"Playback device: This Watch","An automatic phone event must not take over an active Watch session")
        XCTAssertTrue(transport.exists);XCTAssertEqual(transport.label,"Pause Watch")
    }
    func testDimmedScreenCanBeTappedToShowControls(){
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--watch-lifecycle-fixture"];app.launch()
        let play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
        let transport=app.buttons["watch.transport.play"];XCTAssertTrue(transport.waitForExistence(timeout:8))
        app.buttons["watch.fixture.lifecycle"].tap()
        let ambient=app.buttons["watch.ambient"];XCTAssertTrue(ambient.waitForExistence(timeout:5));ambient.tap()
        XCTAssertTrue(transport.waitForExistence(timeout:5));XCTAssertTrue(transport.isHittable)
    }
    func testWakeRestoresControlsBeforeLuminanceRefresh(){
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--watch-lifecycle-fixture"];app.launch()
        let play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
        let transport=app.buttons["watch.transport.play"];XCTAssertTrue(transport.waitForExistence(timeout:8))
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Pause Watch"),object:transport)],timeout:8),.completed)
        transport.tap()
        let lifecycle=app.buttons["watch.fixture.lifecycle"]
        for _ in 0..<3{
            lifecycle.tap();XCTAssertTrue(app.descendants(matching:.any)["watch.ambient"].firstMatch.waitForExistence(timeout:5))
            lifecycle.tap()
            XCTAssertTrue(transport.waitForExistence(timeout:5),"An active scene must restore controls even before the luminance signal catches up")
            XCTAssertTrue(transport.isHittable);XCTAssertEqual(transport.label,"Play Watch")
            lifecycle.tap()
        }
        let queue=app.buttons["watch.queue"];reveal(queue,in:app);queue.tap()
        XCTAssertTrue(app.staticTexts["Up next · 2"].waitForExistence(timeout:5),"Wrist transitions must preserve the queue")
    }
    func testPlaybackAdvancesWhileDimmedAndRestoresOnWake(){
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--watch-lifecycle-fixture"];app.launch()
        let play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
        let transport=app.buttons["watch.transport.play"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Pause Watch"),object:transport)],timeout:8),.completed)
        app.buttons["watch.fixture.lifecycle"].tap()
        XCTAssertTrue(app.buttons["watch.ambient"].waitForExistence(timeout:5))
        let elapsed=expectation(description:"Thirty-five seconds in the dimmed layout")
        DispatchQueue.main.asyncAfter(deadline:.now()+35){elapsed.fulfill()}
        XCTAssertEqual(XCTWaiter.wait(for:[elapsed],timeout:38),.completed)
        app.buttons["watch.fixture.lifecycle"].tap()
        XCTAssertTrue(transport.waitForExistence(timeout:8));XCTAssertEqual(transport.label,"Pause Watch")
        let heading=app.descendants(matching:.any)["watch.track"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout:5));XCTAssertFalse(heading.label.contains("First Light"))
        capture("Watch after dimmed playback and wake");transport.tap()
    }
    func testPlaybackContinuesPastThirtySecondsInBackground(){
        let app=launch(),play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
        let transport=app.buttons["watch.transport.play"]
        XCTAssertTrue(transport.waitForExistence(timeout:8))
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Pause Watch"),object:transport)],timeout:8),.completed)
        XCUIDevice.shared.press(.home)
        let elapsed=expectation(description:"Thirty-five seconds with the app backgrounded")
        DispatchQueue.main.asyncAfter(deadline:.now()+35){elapsed.fulfill()}
        XCTAssertEqual(XCTWaiter.wait(for:[elapsed],timeout:38),.completed)
        app.activate()
        XCTAssertTrue(transport.waitForExistence(timeout:8));XCTAssertEqual(transport.label,"Pause Watch")
        let heading=app.descendants(matching:.any)["watch.track"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout:5));XCTAssertFalse(heading.label.contains("First Light"),"Audio must advance beyond the first twenty-second demo track while backgrounded")
        capture("Watch after background playback")
        transport.tap()
    }
    func testCrownDoesNotScrollTheNowPlayingControls(){
        let app=launch(),play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));reveal(play,in:app);play.tap()
        let transport=app.buttons["watch.transport.play"];XCTAssertTrue(transport.waitForExistence(timeout:8));let initial=transport.frame.minY
        XCUIDevice.shared.rotateDigitalCrown(delta:1)
        XCTAssertTrue(transport.isHittable,"Crown volume must not scroll the player out of view")
        XCTAssertEqual(transport.frame.minY,initial,accuracy:3,"Crown input should reach volume, not page scrolling")
        capture("Watch Crown volume")
        if transport.isHittable,transport.label=="Pause Watch"{transport.tap()}
    }
    func testPhoneNowPlayingLaunchSelectsPhoneControls(){
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--remote-now-playing"];app.launch()
        XCTAssertTrue(app.buttons["watch.remote.reconnect"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons["watch.device"].firstMatch.label,"Playback device: iPhone")
    }
    func testTouchPauseResume(){
        let app=launch(),play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));play.tap()
        let transport=app.buttons["watch.transport.play"]
        func expect(_ label:String){XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@",label),object:transport)],timeout:6),.completed)}
        expect("Pause Watch");transport.tap();expect("Play Watch");transport.tap();expect("Pause Watch");transport.tap();expect("Play Watch")
    }
    func testRemoteCrownVolumeInput()throws{
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--remote-volume-fixture"];app.launch()
        let volume=app.buttons["watch.remote.volume"];XCTAssertTrue(volume.waitForExistence(timeout:10));XCTAssertEqual(volume.value as? String,"50 percent")
        XCUIDevice.shared.rotateDigitalCrown(delta:1)
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value != %@","50 percent"),object:volume)
        XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:5),.completed)
        let text=try XCTUnwrap(volume.value as? String),percent=try XCTUnwrap(Int(text.filter(\.isNumber)))
        XCTAssertTrue((0...100).contains(percent))
        let applied=app.staticTexts["watch.fixture.applied-volume"]
        let acknowledged=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Applied \(percent) percent"),object:applied)
        XCTAssertEqual(XCTWaiter.wait(for:[acknowledged],timeout:5),.completed)
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.contrast,.trait])
        capture("Watch remote Crown volume")
    }
    func testLibraryAndQueueAccessibility()throws{
        let app=launch(),play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15))
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.contrast,.trait])
        app.buttons["watch.device"].firstMatch.tap();XCTAssertTrue(app.buttons["watch.device.watch"].waitForExistence(timeout:5))
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.contrast,.trait])
        app.buttons["watch.device.watch"].tap()
        reveal(play,in:app);play.tap();let queue=app.buttons["watch.queue"];XCTAssertTrue(queue.waitForExistence(timeout:8));reveal(queue,in:app);queue.tap()
        XCTAssertTrue(app.staticTexts["Up next · 2"].waitForExistence(timeout:5))
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.contrast,.trait])
    }
    func testNowPlayingAccessibility()throws{
        let app=launch(),play=app.buttons["watch.play"];XCTAssertTrue(play.waitForExistence(timeout:15));reveal(play,in:app);play.tap()
        let transport=app.buttons["watch.transport.play"];XCTAssertTrue(transport.waitForExistence(timeout:8))
        try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.contrast,.trait])
        if transport.label=="Pause Watch"{transport.tap()}
    }
    func testDimmedPlayerUsesMinimalLayout(){ambientFlow()}
    func testLargeTextDimmedLayout(){ambientFlow(largeText:true)}
    private func ambientFlow(largeText:Bool=false){
        let app=XCUIApplication();app.launchArguments=["--demo","--watch-ui-testing","--watch-dimmed"];if largeText{app.launchArguments.append("--watch-large-text")};app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["watch.ambient"].firstMatch.waitForExistence(timeout:10),"Wrist-down mode must use the ambient player")
        XCTAssertTrue(app.staticTexts["First Light"].exists)
        XCTAssertFalse(app.buttons["watch.transport.play"].isHittable,"The retained transport must be hidden and untappable in Always On mode")
        XCTAssertNoThrow(try app.performAccessibilityAudit(for:[.hitRegion,.sufficientElementDescription,.contrast,.trait]))
        capture("Watch dimmed player")
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
