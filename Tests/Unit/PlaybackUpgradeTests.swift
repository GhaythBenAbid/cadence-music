import XCTest
import AVFoundation
import CadenceCore
@testable import Cadence

@MainActor final class PlaybackUpgradeTests:XCTestCase {
    func testRepeatOneAndManualNextAndPreloading(){
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.play(DemoLibrary.songs,resolver:{DemoLibrary.url($0)})
        XCTAssertEqual(audio.preparedNextID,audio.timeline.upcoming.first?.id)
        audio.repeatMode = .one;XCTAssertNil(audio.preparedNextID)
        // Manual skip continues to the next song even with repeat-one selected.
        audio.next();XCTAssertEqual(audio.current?.id,DemoLibrary.songs[1].id)
        audio.repeatMode = .off;XCTAssertEqual(audio.preparedNextID,audio.timeline.upcoming.first?.id)
        audio.removeUpcoming(audio.timeline.upcoming[0].id);XCTAssertNil(audio.preparedNextID)
    }
    func testNaturalRepeatOneAndAutoplayOnlyAppendNewSongs()async throws{
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        let seed=DemoLibrary.songs[0],next=Song(id:"recommendation",title:"Recommendation",artist:seed.artist)
        audio.play([seed],resolver:{_ in DemoLibrary.url(seed)})
        audio.repeatMode = .one;audio.seek(8);audio.finishedCurrent()
        XCTAssertEqual(audio.current?.id,seed.id);XCTAssertEqual(audio.elapsed,0)
        audio.repeatMode = .off;audio.autoplay=true;audio.relatedSongs={_ in [seed,next,next]}
        audio.finishedCurrent();try await Task.sleep(for:.milliseconds(200))
        XCTAssertEqual(audio.current?.id,next.id);XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(audio.timeline.entries.filter{$0.song.id==next.id}.count,1)
    }
    func testPauseCancelsPendingRecommendationPlayback()async throws{
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.play([DemoLibrary.songs[0]],resolver:{DemoLibrary.url($0)})
        audio.repeatMode = .off;audio.autoplay=true
        audio.relatedSongs={_ in try await Task.sleep(for:.seconds(1));return [DemoLibrary.songs[1]]}
        audio.finishedCurrent();audio.pause();try await Task.sleep(for:.milliseconds(1100))
        XCTAssertFalse(audio.isPlaying);XCTAssertEqual(audio.current?.id,DemoLibrary.songs[0].id);XCTAssertFalse(audio.preparingRelated)
    }
    func testPreparedQueueAdvancesOnActualAudioEnd()async throws{
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.autoplay=false;audio.repeatMode = .off
        audio.play(DemoLibrary.songs,resolver:{DemoLibrary.url($0)})
        let prepared=audio.preparedNextID
        try await Task.sleep(for:.milliseconds(200));audio.seek(19.5)
        for _ in 0..<35 where audio.current?.id==DemoLibrary.songs[0].id{try await Task.sleep(for:.milliseconds(100))}
        XCTAssertEqual(audio.current?.id,DemoLibrary.songs[1].id);XCTAssertEqual(audio.timeline.current?.id,prepared)
    }
    func testSystemCommandsRouteToTheSelectedDeviceInsteadOfResumingLocalAudio(){
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.play([DemoLibrary.songs[0]],resolver:{DemoLibrary.url($0)});audio.pause()
        var routed=0;audio.systemRoute={_ in routed+=1;return true}
        audio.dispatchSystemCommand(PhoneCommand(.play));audio.dispatchSystemCommand(nil)
        XCTAssertFalse(audio.isPlaying);XCTAssertEqual(routed,2)
    }
    func testNetworkRecoveryDoesNotResumeAfterUserPause()async throws{
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.play(DemoLibrary.songs,resolver:{DemoLibrary.url($0)})
        audio.handlePlaybackFailure(NSError(domain:NSURLErrorDomain,code:NSURLErrorNetworkConnectionLost))
        XCTAssertFalse(audio.isPlaying);XCTAssertTrue(audio.error?.contains("Reconnecting")==true)
        audio.pause();try await Task.sleep(for:.seconds(1));XCTAssertFalse(audio.isPlaying)
    }
    func testRemoteQueueEditPreservesPlaybackAndRejectsStaleBaseline()throws{
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.play([DemoLibrary.songs[0]],resolver:{DemoLibrary.url($0)})
        var update=audio.playbackSnapshot();let baseline=update.queue.entries.map(\.id)
        update.queue.append(DemoLibrary.songs[1],next:true)
        try audio.replaceQueue(update,expected:baseline)
        XCTAssertTrue(audio.isPlaying);XCTAssertEqual(audio.current?.id,DemoLibrary.songs[0].id);XCTAssertEqual(audio.upcoming.first?.song.id,DemoLibrary.songs[1].id)
        XCTAssertThrowsError(try audio.replaceQueue(update,expected:baseline))
    }
    func testHandoffRestoresDuplicateQueueEntriesPositionAndLocalVolume()throws{
        let source=PlaybackSnapshot(queue:PlaybackQueue(songs:[DemoLibrary.songs[0],DemoLibrary.songs[0],DemoLibrary.songs[1]]),position:6,repeats:true,volume:0.9,repeatMode:.one,autoplay:false)
        let audio=AudioController();audio.volume=0.2;audio.configureSession(account:"handoff-test",resolver:{DemoLibrary.url($0)});defer{audio.stop()}
        try audio.install(source,autoplay:false)
        XCTAssertEqual(audio.timeline.entries.map(\.id),source.queue.entries.map(\.id));XCTAssertEqual(audio.elapsed,6)
        XCTAssertEqual(audio.volume,0.2);XCTAssertEqual(audio.repeatMode,.one);XCTAssertFalse(audio.autoplay);XCTAssertFalse(audio.isPlaying)
    }
    func testNewSearchQueryIgnoresOldPageAndKeepsLoadedResultsAfterError()async throws{
        let state=CatalogSearchState(),song=DemoLibrary.songs[0]
        await state.load(query:"first",kind:.songs,fetch:{_,_,_ in SearchResults(song:[song])})
        await state.load(query:"first",kind:.songs,fetch:{_,_,_ in throw URLError(.notConnectedToInternet)})
        XCTAssertEqual(state.songs.map(\.id),[song.id]);XCTAssertNotNil(state.error)
        state.reset();XCTAssertTrue(state.songs.isEmpty);XCTAssertNil(state.error)
    }
}
