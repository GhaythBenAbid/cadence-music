import XCTest
import AVFoundation
import CadenceCore
@testable import Cadence

@MainActor final class LiveGlobalSearchTests:XCTestCase {
    func testOptionalLiveGlobalCatalogPreparationAndFullAudio()async throws{
        struct Fixture:Decodable{var url:String;var username:String;var password:String;var allowPreparation:Bool}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLiveGlobalFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires explicit private fixture for one authorized server preparation.")};try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data);guard fixture.allowPreparation else{throw XCTSkip("Preparation not enabled")}
        let credentials=ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password)
        let metadata=GlobalMusicAPI(),api=SubsonicAPI(credentials:credentials),native=AurralDiscoveryAPI(credentials:credentials)
        do{
            let results=try await metadata.search("Wallpaper Kevin MacLeod",kind:.songs)
            let track=try XCTUnwrap(results.first{$0.title=="Wallpaper" && $0.artist=="Kevin MacLeod"})
            let artists=try await metadata.search("Kevin MacLeod",kind:.artists),artist=try XCTUnwrap(artists.first{$0.title=="Kevin MacLeod"})
            let albums=try await metadata.children(artist);XCTAssertFalse(albums.isEmpty)
            let tracks=try await metadata.children(try XCTUnwrap(albums.first));XCTAssertFalse(tracks.isEmpty)
            let initiallyOwned=track.libraryMatch(try await api.search(track.title,kind:.songs,size:100).song ?? [])
            XCTAssertNil(initiallyOwned,"This acceptance check must start with a song outside the library")
            _=try await native.preparationJobs()
            let state=GlobalPlaybackState(),audio=AudioController();audio.volume=0;defer{state.stopWaiting();audio.stop()}
            var played:Song?
            state.start(track,lookup:{track.libraryMatch(try await api.search(track.title,kind:.songs,size:100).song ?? [])},request:{try await native.prepareTrack(track)},jobs:{try await native.preparationJobs()},isCurrent:{true},play:{song in played=song;audio.play([song],resolver:{api.authenticatedURL("stream",parameters:[.init(name:"id",value:$0.id)])})},checks:90)
            for _ in 0..<2100 where state.waiting{try await Task.sleep(for:.milliseconds(100))}
            _=try XCTUnwrap(played,state.message ?? "No full song became available")
            for _ in 0..<100 where audio.elapsed<0.5{try await Task.sleep(for:.milliseconds(100))}
            XCTAssertGreaterThan(audio.elapsed,0.4,"Actual Aurral audio must advance")
            XCTAssertGreaterThan(audio.duration,30,"Catalog previews must not masquerade as full music")
            await native.signOut()
        }catch{await native.signOut();throw error}
    }
}

extension LiveGlobalSearchTests {
    func testOptionalProductionPreparationCenterWithRealAcquisitionAndAudio()async throws{
        struct Fixture:Decodable{var url:String;var username:String;var password:String;var allowPreparation:Bool}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLivePreparationFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires a private authorized preparation fixture.")};try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data);guard fixture.allowPreparation else{throw XCTSkip("Preparation not authorized")}
        let credentials=ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password),api=SubsonicAPI(credentials:ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password)),native=AurralDiscoveryAPI(credentials:ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let center=PreparationCenter(storage:PreparationStore(root:root)),audio=AudioController(sessions:PlaybackSessionStore(root:root.appendingPathComponent("audio")));audio.volume=0;defer{audio.stop()}
        do{
            let result=try await GlobalMusicAPI().search("Cipher Kevin MacLeod",kind:.songs),track=try XCTUnwrap(result.first{$0.title=="Cipher" && $0.artist=="Kevin MacLeod"})
            let wasOwned=track.libraryMatch(try await api.search(track.title,kind:.songs,size:100).song ?? []) != nil;print("Preparation acceptance: initially owned =",wasOwned)
            var requests=0,played=false
            center.configure(credentials.accountKey,lookup:{track in track.libraryMatch(try await api.search(track.title,kind:.songs,size:100).song ?? [])},request:{track in requests+=1;return try await native.prepareTrack(track)},jobs:{try await native.preparationJobs()})
            center.apply={item in let song=try XCTUnwrap(item.song);played=true;audio.play([song],resolver:{api.authenticatedURL("stream",parameters:[.init(name:"id",value:$0.id)])})}
            _=try center.submit([track],action:.play)
            for _ in 0..<90 where !played{await center.sync();if let phase=center.items.first?.phase,[PreparationPhase.failed,.blocked,.uncertain].contains(phase){break};try await Task.sleep(for:.seconds(2))}
            XCTAssertTrue(played,center.items.first?.message ?? "No prepared song");XCTAssertEqual(requests,wasOwned ? 0 : 1)
            for _ in 0..<100 where audio.elapsed<0.5{try await Task.sleep(for:.milliseconds(100))}
            XCTAssertGreaterThan(audio.elapsed,0.4);XCTAssertGreaterThan(audio.duration,30)
            let restored=PreparationCenter(storage:PreparationStore(root:root));restored.configure(credentials.accountKey);XCTAssertEqual(restored.items.first?.phase,.complete)
            await native.signOut()
        }catch{await native.signOut();throw error}
    }
}
