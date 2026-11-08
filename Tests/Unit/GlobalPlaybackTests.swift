import XCTest
import CadenceCore
@testable import Cadence

@MainActor final class GlobalPlaybackTests:XCTestCase {
    let entry=MusicCatalogEntry(id:"outside",kind:.song,title:"Beyond",artist:"Artist")
    private func settle(_ state:GlobalPlaybackState)async{for _ in 0..<200 where state.waiting{await Task.yield()}}
    func testAvailableSongPlaysWithoutRequestingPreparation()async{
        let state=GlobalPlaybackState();var requests=0,played:String?
        state.start(entry,lookup:{Song(id:"owned",title:"Beyond",artist:"Artist")},request:{requests+=1;throw GlobalMusicError.unavailable},jobs:{[]},isCurrent:{true},play:{played=$0.id},interval:.milliseconds(1),checks:2)
        await settle(state);XCTAssertEqual(played,"owned");XCTAssertEqual(requests,0)
    }
    func testUnconfirmedPreparationIsCheckedWithoutSubmittingAgain()async{
        let state=GlobalPlaybackState();var requests=0
        let request:()async throws->TrackPreparationReceipt={requests+=1;throw GlobalMusicError.uncertain}
        state.start(entry,lookup:{nil},request:request,jobs:{[]},isCurrent:{true},play:{_ in XCTFail()},interval:.milliseconds(1),checks:1)
        await settle(state);XCTAssertEqual(requests,1);XCTAssertTrue(state.message?.contains("didn't confirm")==true)
        state.start(entry,lookup:{nil},request:request,jobs:{[]},isCurrent:{true},play:{_ in XCTFail()},interval:.milliseconds(1),checks:1)
        try? await Task.sleep(for:.milliseconds(20));XCTAssertEqual(requests,1);XCTAssertFalse(state.waiting)
    }
    func testAccountResetAndPlaybackChangesPreventDelayedAutoplay()async{
        let state=GlobalPlaybackState();state.configure("first");var continuation:CheckedContinuation<Song?,Never>?
        state.start(entry,lookup:{await withCheckedContinuation{continuation=$0}},request:{throw GlobalMusicError.unavailable},jobs:{[]},isCurrent:{true},play:{_ in XCTFail("Old account must not play")})
        for _ in 0..<100 where continuation==nil{await Task.yield()};state.configure("second");continuation?.resume(returning:Song(id:"old",title:"Beyond"));await Task.yield();XCTAssertNil(state.track);XCTAssertFalse(state.waiting)
        state.start(entry,lookup:{Song(id:"new",title:"Beyond")},request:{throw GlobalMusicError.unavailable},jobs:{[]},isCurrent:{false},play:{_ in XCTFail("Changed playback must not be interrupted")});await settle(state);XCTAssertFalse(state.waiting)
    }
    func testBlockedJobsStayVisibleAndNeverPretendToPlay()async throws{
        let state=GlobalPlaybackState(),receipt=try JSONDecoder().decode(TrackPreparationReceipt.self,from:Data(#"{"success":true,"jobId":"job"}"#.utf8))
        state.start(entry,lookup:{nil},request:{receipt},jobs:{[TrackPreparationJob(id:"job",status:"blocked")]},isCurrent:{true},play:{_ in XCTFail()},interval:.milliseconds(1),checks:2)
        await settle(state);XCTAssertTrue(state.message?.contains("source review")==true);XCTAssertFalse(state.waiting)
    }
}
