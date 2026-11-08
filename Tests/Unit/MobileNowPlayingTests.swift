import XCTest
import AVFoundation
import MediaPlayer
import UIKit
import CadenceCore
@testable import Cadence

@MainActor final class MobileNowPlayingTests:XCTestCase {
    func testPhonePublishesMetadataArtworkTimelineAndTransportChanges()throws {
        let audio=AudioController();audio.volume=0
        defer{audio.stop()}
        let songs=DemoLibrary.songs
        let image=UIGraphicsImageRenderer(size:CGSize(width:20,height:20)).image{context in UIColor.green.setFill();context.fill(CGRect(x:0,y:0,width:20,height:20))}
        let artwork=try XCTUnwrap(image.pngData())
        audio.play(songs,resolver:{DemoLibrary.url($0)},artwork:{_ in artwork})
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(AVAudioSession.sharedInstance().category,.playback)
        XCTAssertTrue((Bundle.main.object(forInfoDictionaryKey:"UIBackgroundModes") as? [String] ?? []).contains("audio"))
        let center=MPNowPlayingInfoCenter.default()
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,songs[0].title)
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyArtist] as? String,songs[0].artist)
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String,songs[0].album)
        XCTAssertNotNil(center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue,1)
        audio.pause()
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue,0)
        audio.seek(5)
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue,5)
        audio.resume();XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue,1)
        audio.next();XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,songs[1].title)
        audio.seek(0);audio.previous();XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,songs[0].title)
        let commands=MPRemoteCommandCenter.shared()
        for command in [commands.playCommand,commands.pauseCommand,commands.togglePlayPauseCommand,commands.nextTrackCommand,commands.previousTrackCommand,commands.changePlaybackPositionCommand]{XCTAssertTrue(command.isEnabled)}
        audio.stop();XCTAssertNil(center.nowPlayingInfo);XCTAssertFalse(audio.isPlaying)
    }
    func testDownloadedAudioUsesTheSamePhoneSystemPlayer()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let downloads=DeviceDownloads(root:root.appendingPathComponent("downloads"));downloads.configure(account:"cadence-demo")
        let song=DemoLibrary.songs[0],source=root.appendingPathComponent("staged.wav")
        try FileManager.default.copyItem(at:try XCTUnwrap(DemoLibrary.url(song)),to:source)
        try downloads.save(source,song:song,account:"cadence-demo")
        let file=try XCTUnwrap(downloads.url(song));XCTAssertTrue(file.isFileURL)
        let playable=try await AVURLAsset(url:file).load(.isPlayable);XCTAssertTrue(playable)
        let audio=AudioController();audio.volume=0;defer{audio.stop()}
        audio.play([song],resolver:{downloads.url($0)})
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,song.title)
        audio.pause();XCTAssertEqual((MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue,0)
    }
}
