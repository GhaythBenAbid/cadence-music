import XCTest
import CadenceCore
@testable import Cadence

final class RemotePlaybackTests:XCTestCase {
    @MainActor func testWatchCommandsControlPhoneQueueAndReturnConfirmedState()throws {
        let store=PhoneStore();store.enterDemo();defer{store.audio.stop()}
        store.play(DemoLibrary.songs)
        let pause=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.pause)))
        XCTAssertFalse(pause.isPlaying);XCTAssertEqual(pause.song?.id,DemoLibrary.songs[0].id)
        let next=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.next)))
        XCTAssertEqual(next.song?.id,DemoLibrary.songs[1].id)
        let previous=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.previous)))
        XCTAssertEqual(previous.song?.id,DemoLibrary.songs[0].id)
        let seek=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.seek,value:7)))
        XCTAssertEqual(seek.elapsed,7)
        let clamped=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.seek,value:1e100)))
        XCTAssertEqual(clamped.elapsed,clamped.duration)
        let volume=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.volume,value:0.25)))
        XCTAssertEqual(volume.volume,0.25)
        let repeatState=try XCTUnwrap(store.bridge.onCommand?(PhoneCommand(.repeatMode,value:0)))
        XCTAssertFalse(repeatState.repeats)
        XCTAssertThrowsError(try store.bridge.onCommand?(PhoneCommand(.volume,value:4)))
        XCTAssertEqual(store.audio.volume,0.25)
    }
}
