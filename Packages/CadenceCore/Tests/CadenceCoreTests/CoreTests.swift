import XCTest
@testable import CadenceCore
final class CoreTests: XCTestCase {
    let credentials=ServerCredentials(server:URL(string:"https://music.example:8443")!,username:"runner",password:"Secret+&?#")
    func testAuthenticationAndFormEncoding() throws {
        let api=SubsonicAPI(credentials:credentials)
        let items=api.authentication(salt:"fixed")
        XCTAssertEqual(items.first(where:{$0.name=="t"})?.value,"42be3ab08212938269c4a6c99305b113")
        let request=api.request("search3",parameters:[.init(name:"query",value:"A+B & C")])
        XCTAssertEqual(request.url?.absoluteString,"https://music.example:8443/rest/search3.view")
        let body=String(data:request.httpBody!,encoding:.utf8)!
        XCTAssertTrue(body.contains("A%2BB%20%26%20C"));XCTAssertFalse(body.contains(credentials.password))
    }
    func testServerValidation() throws {
        XCTAssertEqual(try ServerCredentials.normalizedServer(" https://music.example:8443/rest/ ").absoluteString,"https://music.example:8443")
        XCTAssertThrowsError(try ServerCredentials.normalizedServer("http://music.example"))
        XCTAssertThrowsError(try ServerCredentials.normalizedServer("https://user:password@music.example"))
        XCTAssertNotEqual(credentials.accountKey,ServerCredentials(server:credentials.server,username:"other",password:credentials.password).accountKey)
    }
    func testOptionalFieldsAndServerErrors() throws {
        let data=Data(#"{"subsonic-response":{"status":"ok","albumList2":{"album":[{"id":"a","name":"Run"}]},"searchResult3":{"song":[{"id":"s","title":"Song","duration":205}]}}}"#.utf8)
        let response=try JSONDecoder().decode(SubsonicEnvelope.self,from:data).response.checked()
        XCTAssertEqual(response.albumList2?.album?.first?.artist,nil)
        XCTAssertEqual(response.searchResult3?.song?.first?.durationLabel,"3:25")
        let failed=Data(#"{"subsonic-response":{"status":"failed","error":{"code":40,"message":"Wrong username or password"}}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SubsonicEnvelope.self,from:failed).response.checked())
    }
    func testManifestAndIntegrityRejectCorruption() throws {
        let song=Song(id:"../../unsafe",title:"Run")
        XCTAssertFalse(song.filename.contains("/"))
        let mix=try RunMix(accountKey:credentials.accountKey,name:"Easy miles",songs:[song])
        XCTAssertThrowsError(try RunMix(accountKey:credentials.accountKey,name:"Duplicate",songs:[song,song]))
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("audio fixture".utf8).write(to:temp);defer {try? FileManager.default.removeItem(at:temp)}
        let transfer=TrackTransfer(mix:mix,songID:song.id,bytes:13,sha256:try FileIntegrity.sha256(temp))
        XCTAssertNoThrow(try FileIntegrity.verify(temp,transfer:transfer))
        try Data("corrupt audio".utf8).write(to:temp)
        XCTAssertThrowsError(try FileIntegrity.verify(temp,transfer:transfer))
    }
}

final class CompanionPlaybackTests:XCTestCase {
    func testPlaybackUpdatesPreserveMixAndEraseTombstone(){
        let mix=Data("mix".utf8),state=Data("playback".utf8)
        let withMix=CompanionContext.update(["mix":mix,"version":1],fields:["playback":state])
        XCTAssertEqual(withMix["mix"] as? Data,mix)
        let erased=CompanionContext.update(withMix,fields:["clearAt":123.0])
        XCTAssertNil(erased["mix"]);XCTAssertEqual(erased["playback"] as? Data,state)
        let refreshed=CompanionContext.update(erased,fields:["playback":Data()])
        XCTAssertEqual(refreshed["clearAt"] as? Double,123)
        let newMix=CompanionContext.update(refreshed,fields:["mix":mix])
        XCTAssertNil(newMix["clearAt"])
    }
    func testRemoteCommandsRejectUnsafeValues()throws {
        XCTAssertThrowsError(try PhoneCommand(.volume,value:2).validate())
        XCTAssertThrowsError(try PhoneCommand(.seek,value:.infinity).validate())
        XCTAssertThrowsError(try PhoneCommand(.seek,value:-1).validate())
        XCTAssertThrowsError(try PhoneCommand(.shuffle).validate())
        try PhoneCommand(.volume,value:0.5).validate();try PhoneCommand(.seek,value:205).validate()
    }
    func testNowPlayingRoundTripIncludesPauseStateAndTrack()throws {
        let state=PhonePlayback(song:Song(id:"test",title:"Music"),isPlaying:false,elapsed:12,duration:205,shuffled:true,repeats:false,volume:0.7)
        let decoded=try JSONDecoder().decode(PhonePlayback.self,from:JSONEncoder().encode(state))
        XCTAssertEqual(decoded.song?.id,"test");XCTAssertFalse(decoded.isPlaying);XCTAssertEqual(decoded.elapsed,12);XCTAssertEqual(decoded.volume,0.7)
    }
}
