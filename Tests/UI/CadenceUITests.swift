import XCTest
final class CadenceUITests:XCTestCase{
    @MainActor func testDemoLibraryPlaybackAndRunScreen(){
        let app=demo()
        XCTAssertTrue(app.staticTexts["Find your\nrhythm."].waitForExistence(timeout:15))
        save(app,"01-library")
        for _ in 0..<4 where !app.staticTexts["Your next easy run"].firstMatch.isHittable{app.swipeUp()}
        app.staticTexts["Your next easy run"].firstMatch.tap()
        let play=app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout:10));play.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:10))
        save(app,"02-collection-playback")
        app.tabBars.buttons["Your run"].tap()
        XCTAssertTrue(app.staticTexts["Just you.\nAnd your music."].waitForExistence(timeout:5))
        save(app,"03-watch-preparation")
        app.tabBars.buttons["Search"].tap();app.segmentedControls.buttons["My library"].tap()
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Homeward")
        XCTAssertTrue(app.staticTexts["Homeward"].firstMatch.waitForExistence(timeout:8))
        save(app,"04-search")
    }
    @MainActor func testPhoneDownloadsAreSavedAndSurviveRelaunch(){
        let app=demo()
        app.tabBars.buttons["Search"].tap();app.segmentedControls.buttons["My library"].tap()
        let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Homeward\n")
        let download=app.buttons["Download Homeward to iPhone"].firstMatch
        let remove=app.buttons["Remove download for Homeward"].firstMatch
        if remove.waitForExistence(timeout:2){remove.tap();app.buttons["Remove download"].firstMatch.tap()}
        XCTAssertTrue(download.waitForExistence(timeout:8));download.tap()
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.staticTexts["Homeward"].firstMatch.waitForExistence(timeout:8))
        app.buttons["Play downloads"].tap();XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:5));save(app,"08-iphone-downloads")
        app.terminate();app.launch()
        if app.buttons["login.demo"].waitForExistence(timeout:2){app.swipeUp();app.buttons["login.demo"].tap()}
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.staticTexts["Homeward"].firstMatch.waitForExistence(timeout:8))
    }
    @MainActor func testQueuePlaylistAndPausedResume(){
        let app=demo()
        app.tabBars.buttons["Search"].tap();app.segmentedControls.buttons["My library"].tap()
        let search=app.searchFields.firstMatch;search.tap();search.typeText("Homeward\n")
        XCTAssertTrue(app.staticTexts["Homeward"].firstMatch.waitForExistence(timeout:8))
        app.buttons["song.play.demo-homeward"].tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:5));app.buttons["Pause"].firstMatch.tap()
        app.buttons["Options for Homeward"].firstMatch.tap();app.buttons["Play next"].tap()
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout:8));XCTAssertFalse(app.buttons["Pause"].exists)
        app.buttons["player.open"].tap()
        XCTAssertTrue(app.buttons["Open queue"].waitForExistence(timeout:5));app.buttons["Open queue"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout:5));save(app,"09-queue")
        app.buttons["Done"].tap();app.buttons["Close player"].tap()
        app.tabBars.buttons["Listen"].tap()
        let newPlaylist=app.buttons["playlist.new"]
        for _ in 0..<5 where !newPlaylist.isHittable{app.swipeUp()}
        newPlaylist.tap()
        let name=app.textFields["playlist.name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("UI playlist")
        let find=app.textFields["playlist.search"];find.tap();find.typeText("Homeward")
        let add=app.buttons["Add Homeward to playlist"];XCTAssertTrue(add.waitForExistence(timeout:8));add.tap()
        app.buttons["playlist.save"].tap()
        XCTAssertTrue(app.staticTexts["UI playlist"].firstMatch.waitForExistence(timeout:8));save(app,"10-playlist")
    }
    @MainActor func testDiscoverShowsNewReleasesAndPreviewThenFullLibraryPlayback(){
        let app=demo();app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.staticTexts["A little discovery."].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["New releases"].firstMatch.exists);XCTAssertTrue(app.staticTexts["Fresh Light"].exists);save(app,"11-discover")
        let artist=app.buttons["discover.artist.11111111-1111-1111-1111-111111111111"].firstMatch
        for _ in 0..<4 where !artist.isHittable{app.swipeUp()};artist.tap()
        XCTAssertTrue(app.staticTexts["Popular songs to explore"].waitForExistence(timeout:8))
        let preview=app.buttons["Preview First Light"];XCTAssertTrue(preview.waitForExistence(timeout:5));preview.tap()
        XCTAssertTrue(app.buttons["Stop preview for First Light"].waitForExistence(timeout:5))
        app.buttons["Play First Light from library"].tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["Stop preview for First Light"].exists);save(app,"12-discovery-playback")
        app.tabBars.buttons["Listen"].tap();app.buttons["account.open"].tap();XCTAssertTrue(app.navigationBars["Your corner"].waitForExistence(timeout:5))
    }
    @MainActor func testSpotifyPlaylistLinkPreviewAndDemoCannotSubmit(){
        let app=demo(),open=app.buttons["spotify.open"]
        for _ in 0..<5 where !open.isHittable{app.swipeUp()};XCTAssertTrue(open.waitForExistence(timeout:5));open.tap()
        let imported=app.buttons["spotify.playlist.demo-import"]
        XCTAssertTrue(imported.waitForExistence(timeout:8));XCTAssertTrue(app.navigationBars["Import from Spotify"].waitForExistence(timeout:5));save(app,"14-import-results")
        imported.tap();XCTAssertTrue(app.staticTexts["3 songs ready to play · 3 tracks requested"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Play all available"].isEnabled);app.navigationBars.buttons.firstMatch.tap()

        let link=app.textFields["spotify.link"];for _ in 0..<5 where !link.isHittable{app.swipeUp()};link.tap();link.typeText("https://open.spotify.com/playlist/37i9dQZF1DZ06evNZVVBPG")
        let check=app.buttons["spotify.preview"];XCTAssertTrue(check.isEnabled);check.tap()
        XCTAssertTrue(app.staticTexts["3 tracks · 0 skipped"].waitForExistence(timeout:5))
        let name=app.textFields["spotify.name"];for _ in 0..<5 where !name.isHittable{app.swipeUp()};XCTAssertTrue((name.value as? String ?? "").contains("Spotify playlist"));name.tap();name.typeText("My Spotify picks\n")
        let submit=app.buttons["spotify.import"];for _ in 0..<3 where !submit.isHittable{app.swipeUp()}
        XCTAssertTrue(submit.exists);XCTAssertFalse(submit.isEnabled);save(app,"13-spotify-import")
    }
    @MainActor func testRichSearchArtistAlbumAndPlaybackDevices(){
        let app=demo();app.tabBars.buttons["Search"].tap();app.segmentedControls.buttons["My library"].tap()
        let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Cadence\n")
        app.segmentedControls.buttons["Artists"].tap()
        let artist=app.buttons["Cadence Sessions"].firstMatch;XCTAssertTrue(artist.waitForExistence(timeout:8));artist.tap()
        let album=app.buttons["artist.album.demo-album"].firstMatch;XCTAssertTrue(album.waitForExistence(timeout:8));album.tap()
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout:8));app.buttons["Play"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:5))
        app.buttons["player.devices"].tap();XCTAssertTrue(app.navigationBars["Playback devices"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["This iPhone"].exists);save(app,"15-playback-devices");app.buttons["Done"].tap()
    }
    @MainActor func testGlobalSearchIsDefaultAndFindsOutsideTheLibrary(){
        let app=demo();app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All music"].waitForExistence(timeout:5))
        let field=app.searchFields.firstMatch;field.tap();field.typeText("Beyond the Library\n")
        XCTAssertTrue(app.buttons["catalog.play.demo-outside"].waitForExistence(timeout:8))
        app.segmentedControls.buttons["My library"].tap()
        XCTAssertFalse(app.buttons["catalog.play.demo-outside"].exists)
        XCTAssertTrue(app.staticTexts["No matching songs in your library."].waitForExistence(timeout:8))
    }
    @MainActor func testCatalogAlbumActionsFollowAndPersistentPreparation(){
        let app=demo();app.tabBars.buttons["Search"].tap()
        let field=app.searchFields.firstMatch;field.tap();field.typeText("Cadence\n");app.segmentedControls.buttons["Artists"].tap()
        let artist=app.buttons["Cadence Sessions"].firstMatch;XCTAssertTrue(artist.waitForExistence(timeout:8));artist.tap()
        let follow=app.buttons["Follow artist"];if follow.waitForExistence(timeout:2){follow.tap()}
        XCTAssertTrue(app.buttons["Unfollow artist"].waitForExistence(timeout:5))
        let album=app.buttons["Easy Miles, Cadence Sessions"].firstMatch
        if album.waitForExistence(timeout:3){album.tap()}else{app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Easy Miles")).firstMatch.tap()}
        let play=app.buttons["Play album"];XCTAssertTrue(play.waitForExistence(timeout:5));play.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:10))
        let preparing=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Preparing music ·")).firstMatch;XCTAssertTrue(preparing.waitForExistence(timeout:5));preparing.tap()
        XCTAssertTrue(app.navigationBars["Preparing music"].waitForExistence(timeout:5));save(app,"16-persistent-preparation")
        app.terminate();app.launch();app.tabBars.buttons["Listen"].tap()
        let history=app.buttons["Your listening"];for _ in 0..<4 where !history.isHittable{app.swipeUp()};XCTAssertTrue(history.waitForExistence(timeout:5));history.tap()
        XCTAssertTrue(app.staticTexts["Artists you follow"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Unfollow"].exists)
    }
    @MainActor func testCreatePlaylistFromCatalogBeforeAudioIsAvailable(){
        let app=demo();app.tabBars.buttons["Search"].tap();let field=app.searchFields.firstMatch;field.tap();field.typeText("Beyond the Library\n")
        let options=app.buttons["Options for Beyond the Library"];XCTAssertTrue(options.waitForExistence(timeout:8));options.tap();app.buttons["Add to playlist"].tap()
        let name=app.textFields["catalog.playlist.name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("Catalog pending picks\n")
        app.buttons["catalog.playlist.create"].tap()
        XCTAssertFalse(name.waitForExistence(timeout:2))
        app.tabBars.buttons["Listen"].tap()
        let playlist=app.staticTexts["Catalog pending picks"].firstMatch;for _ in 0..<4 where !playlist.isHittable{app.swipeUp()};XCTAssertTrue(playlist.waitForExistence(timeout:5));save(app,"17-catalog-playlist")
    }
    @MainActor func testWelcomeValidation(){
        let app=XCUIApplication();app.launch()
        if app.tabBars.buttons["Listen"].exists{
            app.tabBars.buttons["Listen"].tap();app.buttons["account.open"].tap();app.buttons["Leave demo"].tap();app.buttons["Sign out"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["login.demo"].waitForExistence(timeout:10))
        let server=app.textFields["login.server"]
        XCTAssertTrue(server.exists)
        XCTAssertEqual(server.value as? String,"https://music.example.com")
        app.buttons["login.connect"].tap()
        XCTAssertTrue(app.alerts["A little pause"].waitForExistence(timeout:5))
        XCTAssertTrue(app.alerts.staticTexts["Enter an HTTPS server address, without credentials."].exists)
        app.alerts.buttons["OK"].tap()
        server.tap();server.typeText("https://music.example.com")
        app.swipeUp()
        app.buttons["login.connect"].tap()
        XCTAssertTrue(app.alerts["A little pause"].waitForExistence(timeout:5))
        XCTAssertTrue(app.alerts.staticTexts["Enter your username and password."].exists)
        app.alerts.buttons["OK"].tap();save(app,"05-welcome")
    }
    @MainActor private func demo()->XCUIApplication{
        let app=XCUIApplication();app.launchArguments=["--demo"];app.launch()
        if app.buttons["login.demo"].waitForExistence(timeout:2){app.swipeUp();app.buttons["login.demo"].tap()}
        if app.tabBars.buttons["Listen"].waitForExistence(timeout:5){app.tabBars.buttons["Listen"].tap()}
        return app
    }
    @MainActor private func save(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
