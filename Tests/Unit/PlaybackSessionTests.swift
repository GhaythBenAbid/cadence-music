import XCTest
import CadenceCore
@testable import Cadence

final class PlaybackSessionTests:XCTestCase {
    @MainActor func testRestoreIsPausedAndWatchCommandUsesRestoredQueue()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let sessions=PlaybackSessionStore(root:root)
        try sessions.save(PlaybackSnapshot(queue:PlaybackQueue(songs:DemoLibrary.songs),position:7,repeats:false,volume:0.3),account:"a")
        let audio=AudioController(sessions:sessions)
        audio.configureSession(account:"a",resolver:{DemoLibrary.url($0)})
        XCTAssertEqual(audio.current?.id,DemoLibrary.songs[0].id);XCTAssertFalse(audio.isPlaying);XCTAssertEqual(audio.elapsed,7)
        try audio.apply(PhoneCommand(.next));XCTAssertEqual(audio.current?.id,DemoLibrary.songs[1].id)
        audio.pause();audio.configureSession(account:"b",resolver:{DemoLibrary.url($0)})
        XCTAssertNil(audio.current);XCTAssertTrue(audio.timeline.entries.isEmpty);XCTAssertFalse(audio.isPlaying)
        audio.configureSession(account:"a",resolver:{DemoLibrary.url($0)})
        XCTAssertEqual(audio.current?.id,DemoLibrary.songs[1].id);XCTAssertFalse(audio.isPlaying)
        audio.stop();XCTAssertNil(sessions.load(account:"a"))
    }
    @MainActor func testEditedPlaylistsRemainPlayableInDemo()async throws{
        let store=PhoneStore();store.enterDemo();defer{store.audio.stop()}
        try await store.savePlaylist(name:"Fixture",songs:[DemoLibrary.songs[1],DemoLibrary.songs[0]])
        let playlist=try XCTUnwrap(store.playlists.first{$0.name=="Fixture"})
        let songs=try await store.songs(for:playlist);XCTAssertEqual(songs.map(\.id),[DemoLibrary.songs[1].id,DemoLibrary.songs[0].id])
        try await store.add(DemoLibrary.songs[2],to:playlist)
        let updated=try await store.playlistForEditing(playlist.id);XCTAssertEqual(updated.entry?.count,3)
        try await store.deletePlaylist(updated);XCTAssertFalse(store.playlists.contains{$0.id==playlist.id})
    }
}
