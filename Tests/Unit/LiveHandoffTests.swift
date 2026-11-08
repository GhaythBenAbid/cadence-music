import XCTest
import AVFoundation
import CadenceCore
@testable import Cadence

@MainActor final class LiveHandoffTests:XCTestCase {
    /// Explicit local fixture is required: this temporarily transfers the running Mac queue.
    func testOptionalRealMacRoundTripWithActualAudio()async throws{
        struct Fixture:Decodable{var url:String;var username:String;var password:String;var host:String;var allowLivePlayback:Bool}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLiveHandoffFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires explicit private Mac playback fixture.")};try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data)
        guard fixture.allowLivePlayback else{throw XCTSkip("Live playback transfer was not authorized by the local fixture.")}
        let credentials=ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password)
        let preferences=UserDefaults(suiteName:"real-handoff-"+UUID().uuidString)!,client=PrivateMacClient(preferences:preferences)
        client.configure(credentials);try client.select(MacEndpoint(id:UUID().uuidString,name:"Live Mac",host:fixture.host))
        let original=try await client.transfer(PlaybackTransfer(.inspect))
        guard !original.snapshot.queue.entries.isEmpty else{throw XCTSkip("The Mac needs a queue to transfer.")}
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        let api=SubsonicAPI(credentials:credentials)
        audio.configureSession(account:"live-handoff",resolver:{api.authenticatedURL("stream",parameters:[.init(name:"id",value:$0.id)])})
        do{
            let transferred=try await client.transfer(PlaybackTransfer(.toPhone))
            try audio.install(transferred.snapshot,autoplay:true)
            let paused=try await client.fetch();XCTAssertFalse(paused.isPlaying)
            XCTAssertEqual(audio.timeline.entries.map(\.id),original.snapshot.queue.entries.map(\.id))
            do{
                let start=audio.elapsed
                for _ in 0..<60 where audio.elapsed<start+0.5{try await Task.sleep(for:.milliseconds(100))}
                XCTAssertGreaterThan(audio.elapsed,start+0.4,"Real streamed audio must advance, not just publish a playing flag")
            }
            let snapshot=audio.playbackSnapshot();audio.pause()
            let back=try await client.transfer(PlaybackTransfer(.toMac,snapshot:snapshot,play:original.play))
            XCTAssertEqual(back.snapshot.queue.entries.map(\.id),original.snapshot.queue.entries.map(\.id))
            XCTAssertEqual(back.play,original.play)
            _=try await client.transfer(PlaybackTransfer(.toMac,snapshot:original.snapshot,play:original.play))
        }catch{
            audio.pause()
            // Always attempt to restore the user's original Mac queue before reporting failure.
            _=try? await client.transfer(PlaybackTransfer(.toMac,snapshot:original.snapshot,play:original.play))
            throw error
        }
    }
}
