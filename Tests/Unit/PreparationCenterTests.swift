import XCTest
import CadenceCore
@testable import Cadence

@MainActor final class PreparationCenterTests:XCTestCase {
    let entry=MusicCatalogEntry(id:"one",kind:.song,title:"One",artist:"Artist")
    private func storage()->PreparationStore{let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);addTeardownBlock{try? FileManager.default.removeItem(at:root)};return PreparationStore(root:root)}
    func testRelaunchRestoresUncertainRequestsAndNeverSubmitsOrPlaysAgain()async throws{
        let storage=storage();var requests=0
        var first:PreparationCenter?=PreparationCenter(storage:storage)
        first!.configure("account",lookup:{_ in nil},request:{_ in requests+=1;throw GlobalMusicError.uncertain},jobs:{[]})
        _=try first!.submit([entry],action:.play);await first!.sync();XCTAssertEqual(requests,1);first=nil
        let restored=PreparationCenter(storage:storage);restored.configure("account",lookup:{_ in Song(id:"ready",title:"One")},request:{_ in requests+=1;throw GlobalMusicError.unavailable},jobs:{[]});var plays=0;restored.apply={_ in plays+=1}
        await restored.sync();XCTAssertEqual(requests,1);XCTAssertEqual(plays,0);XCTAssertEqual(restored.items[0].phase,.ready);XCTAssertTrue(restored.items[0].reviewBeforeApplying)
        restored.allow(restored.items[0].groupID);await restored.sync();XCTAssertEqual(plays,1)
    }
    func testPlayAlbumDeliversInOrderAndNextAlbumInReverseInsertionOrder()async throws{
        let second=MusicCatalogEntry(id:"two",kind:.song,title:"Two",artist:"Artist"),center=PreparationCenter(storage:storage());var ready=Set(["two"]),applied:[String]=[]
        center.configure("account",lookup:{ready.contains($0.id) ? Song(id:$0.id,title:$0.title) : nil},request:{_ in try JSONDecoder().decode(TrackPreparationReceipt.self,from:Data(#"{"success":true,"jobId":"pending"}"#.utf8))},jobs:{[]});center.apply={applied.append($0.entry.id)}
        _=try center.submit([entry,second],action:.play);await center.sync();XCTAssertTrue(applied.isEmpty)
        ready.insert("one");await center.sync();XCTAssertEqual(applied,["one","two"])
        _=try center.submit([entry,second],action:.playNext);await center.sync();XCTAssertEqual(Array(applied.suffix(2)),["two","one"])
    }
    func testAccountSwitchAndRemovalFenceInFlightLookup()async throws{
        let center=PreparationCenter(storage:storage());var finish:CheckedContinuation<Song?,Never>?,requests=0
        center.configure("first",lookup:{_ in await withCheckedContinuation{finish=$0}},request:{_ in requests+=1;throw GlobalMusicError.unavailable},jobs:{[]});_=try center.submit([entry],action:.enqueue);let work=Task{await center.sync()}
        for _ in 0..<100 where finish==nil{await Task.yield()};center.remove(center.items[0].id);finish?.resume(returning:nil);await work.value;XCTAssertEqual(requests,0);XCTAssertEqual(center.items[0].phase,.stopped)
        center.configure("second",lookup:{_ in nil},request:{_ in throw GlobalMusicError.unavailable},jobs:{[]});XCTAssertTrue(center.items.isEmpty)
    }
    func testFailedAlbumSongDoesNotBlockOtherSongsAndActionsNeedExplicitReviewAfterAmbiguity()async throws{
        let second=MusicCatalogEntry(id:"two",kind:.song,title:"Two",artist:"Artist"),center=PreparationCenter(storage:storage());var applied:[String]=[]
        center.configure("account",lookup:{$0.id=="two" ? Song(id:"two",title:"Two") : nil},request:{_ in try JSONDecoder().decode(TrackPreparationReceipt.self,from:Data(#"{"success":true,"jobId":"bad"}"#.utf8))},jobs:{[TrackPreparationJob(id:"bad",status:"blocked")]});center.apply={applied.append($0.entry.id)}
        _=try center.submit([entry,second],action:.play);await center.sync();await center.sync();XCTAssertEqual(center.items.first?.phase,.blocked);XCTAssertEqual(applied,["two"])
    }
}

extension PreparationCenterTests {
    func testUnreadableArchiveIsPreservedAndCannotTriggerNewRequests()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let storage=PreparationStore(root:root),original=PreparationCenter(storage:storage);original.configure("account");_=try original.submit([entry],action:.play)
        let file=try XCTUnwrap(FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).first);let newer=Data("{\"version\":99,\"items\":[]}".utf8);try newer.write(to:file)
        let center=PreparationCenter(storage:storage);var requests=0
        center.configure("account",lookup:{_ in nil},request:{_ in requests+=1;throw GlobalMusicError.unavailable},jobs:{[]});await center.sync();XCTAssertEqual(requests,0);XCTAssertThrowsError(try center.submit([entry],action:.play));XCTAssertEqual(try Data(contentsOf:file),newer)
    }
}

extension PreparationCenterTests {
    func testPlayNextIntoAnEmptyQueueKeepsAlbumOrderWithoutStartingAudio()async throws{
        let center=PreparationCenter(storage:storage()),audio=AudioController();defer{audio.stop()}
        let second=MusicCatalogEntry(id:"two",kind:.song,title:"Two",artist:"Artist")
        audio.configureSession(account:"test",resolver:{_ in URL(fileURLWithPath:"/nonexistent")})
        center.configure("account",lookup:{Song(id:$0.id,title:$0.title)},request:{_ in throw GlobalMusicError.unavailable},jobs:{[]});center.hasPlaybackQueue={audio.current != nil};center.apply={item in audio.enqueue(try XCTUnwrap(item.song),next:item.action == .playNext)}
        _=try center.submit([entry,second],action:.playNext);await center.sync();XCTAssertEqual(audio.timeline.entries.map{$0.song.id},["one","two"]);XCTAssertFalse(audio.isPlaying)
    }
}

extension PreparationCenterTests {
    func testAFullQueueReportsFailureWithoutClaimingAnAdditionalSongWasQueued()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let audio=AudioController(sessions:PlaybackSessionStore(root:root));defer{audio.stop()};audio.configureSession(account:"test",resolver:{_ in URL(fileURLWithPath:"/nonexistent")})
        let songs=(0..<1000).map{Song(id:String($0),title:"Song")};try audio.install(PlaybackSnapshot(queue:PlaybackQueue(songs:songs),position:0,repeats:false,volume:1),autoplay:false)
        XCTAssertThrowsError(try audio.enqueueChecked(Song(id:"extra",title:"Extra")));XCTAssertEqual(audio.timeline.entries.count,1000)
    }
}
