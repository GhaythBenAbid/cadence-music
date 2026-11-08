import XCTest
import MediaPlayer
import CadenceCore

@MainActor final class NowPlayingTests:XCTestCase {
    func testPlayPauseResumeStopPublishesMacSystemState()throws {
        let audio=AudioController()
        defer{audio.stop()}
        audio.volume=0
        let song=Song(id:"media-test",title:"System player test",artist:"Cadence",duration:120)
        audio.play([song],resolver:{_ in URL(fileURLWithPath:"/nonexistent-media-fixture.wav")})
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,song.title)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState,.playing)
        audio.pause();XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState,.paused)
        audio.resume();XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState,.playing)
        audio.stop();XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState,.stopped)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }
}
