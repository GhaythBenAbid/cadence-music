import XCTest
import AVFoundation
import CadenceCore
@testable import Cadence

final class PhoneDownloadsTests:XCTestCase {
    @MainActor func testDownloadsPersistAndWatchEraseDoesNotDeleteThem()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let downloads=DeviceDownloads(root:root.appendingPathComponent("phone"));downloads.configure(account:"cadence-demo")
        let song=DemoLibrary.songs[0],source=root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try Data("fixture audio".utf8).write(to:source);try downloads.save(source,song:song,account:"cadence-demo")
        let reloaded=DeviceDownloads(root:root.appendingPathComponent("phone"));reloaded.configure(account:"cadence-demo")
        XCTAssertEqual(reloaded.songs.map(\.id),[song.id]);XCTAssertNotNil(reloaded.url(song))
        let watch=LocalLibrary(root:root.appendingPathComponent("watch"));watch.clear()
        XCTAssertTrue(reloaded.contains(song))
        reloaded.configure(account:String(repeating:"a",count:64));XCTAssertTrue(reloaded.songs.isEmpty);XCTAssertNil(reloaded.url(song))
        XCTAssertThrowsError(try reloaded.save(root,song:song,account:"cadence-demo"))
        reloaded.configure(account:"cadence-demo");try reloaded.remove(song)
        XCTAssertFalse(reloaded.contains(song));reloaded.configure(account:"cadence-demo");XCTAssertTrue(reloaded.songs.isEmpty)
    }
    @MainActor func testPhoneDownloadQueueSavesOriginalDemoAudio()async throws{
        let store=PhoneStore();store.enterDemo();defer{store.cancelDownloads();store.audio.stop()}
        let song=DemoLibrary.songs[0]
        if store.downloads.contains(song){try store.downloads.remove(song)}
        store.download([song,song])
        for _ in 0..<40 where !store.downloads.contains(song){try await Task.sleep(for:.milliseconds(50))}
        XCTAssertTrue(store.downloads.contains(song));XCTAssertEqual(store.downloads.songs.filter{$0.id==song.id}.count,1)
        let file=try XCTUnwrap(store.downloads.url(song)),original=try XCTUnwrap(DemoLibrary.url(song))
        XCTAssertEqual(try FileIntegrity.sha256(file),try FileIntegrity.sha256(original))
        try store.downloads.remove(song)
    }
}

extension PhoneDownloadsTests {
    @MainActor func testOptionalLiveBackgroundDownload()async throws{
        struct Fixture:Decodable {var url:String;var username:String;var password:String;var song:Song}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLiveDownloadFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires a private local verification fixture.")}
        try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data)
        let credentials=ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password)
        let manager=PhoneDownloadManager.shared;manager.configure(credentials)
        defer{manager.cancelAll();try? manager.downloads.remove(fixture.song);manager.configure(nil)}
        if manager.downloads.contains(fixture.song){try manager.downloads.remove(fixture.song)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sender=BackgroundWatchSender(),local=LocalLibrary(root:root.appendingPathComponent("audio"),preferences:UserDefaults(suiteName:UUID().uuidString)!)
        let preparation=WatchPreparation(local:local,transport:sender,root:root.appendingPathComponent("plan"),available:{manager.downloads.url($0)},requestDownloads:{manager.enqueue($0)})
        let previousHook=manager.onFilesReady;manager.onFilesReady={await preparation.flush()}
        defer{preparation.cancel();manager.onFilesReady=previousHook;try? FileManager.default.removeItem(at:root)}
        try preparation.start(name:"Live background verification",songs:[fixture.song],account:credentials.accountKey)
        for _ in 0..<100 where manager.jobs.first?.state != .running{try await Task.sleep(for:.milliseconds(50))}
        let job=try XCTUnwrap(manager.jobs.first);XCTAssertEqual(job.state,.running)
        manager.pause(job.id);XCTAssertEqual(manager.jobs.first?.state,.paused)
        try await Task.sleep(for:.milliseconds(500));manager.retry(job.id)
        for _ in 0..<3000 where !manager.downloads.contains(fixture.song){
            if manager.jobs.first?.state == .failed{XCTFail("Background transfer failed; see Downloads retry state.");break}
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertTrue(manager.downloads.contains(fixture.song),"Download state: \(manager.jobs.first?.state.rawValue ?? "none"), progress: \(manager.jobs.first?.progress ?? -1)");XCTAssertTrue(manager.jobs.isEmpty)
        await preparation.flush()
        XCTAssertEqual(sender.sent.map(\.songID),[fixture.song.id])
        XCTAssertTrue(preparation.active) // Only a real Watch receipt can mark the mix ready.
        let url=try XCTUnwrap(manager.downloads.url(fixture.song));let asset=AVURLAsset(url:url)
        let playable=try await asset.load(.isPlayable);XCTAssertTrue(playable)
    }
}

@MainActor private final class BackgroundWatchSender:WatchMixSending {
    var canTransfer=true
    var receipt:WatchReceipt?
    var sent:[TrackTransfer]=[]
    func sendMix(_ mix:RunMix)throws{}
    func sendFile(_ file:URL,payload:TrackTransfer)throws{try FileIntegrity.verify(file,transfer:payload);sent.append(payload)}
    func cancelOutstanding(){}
    func resetReceipt(){receipt=nil}
    func outstandingSongIDs(for mix:RunMix)->Set<String>{Set(sent.map(\.songID))}
}

extension PhoneDownloadsTests {
    @MainActor func testBackgroundCompletionWaitsForWatchStaging()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager=PhoneDownloadManager(configuration:.ephemeral,root:root,downloads:DeviceDownloads(root:root.appendingPathComponent("audio")),credentials:nil)
        defer{manager.close();try? FileManager.default.removeItem(at:root)}
        for _ in 0..<1000 where !manager.restored{await Task.yield()}
        XCTAssertTrue(manager.restored)
        var release:CheckedContinuation<Void,Never>?,completed=false
        manager.onFilesReady={await withCheckedContinuation{release=$0}}
        manager.backgroundCompletion={completed=true}
        let finish=Task{await manager.finishBackgroundEvents()}
        for _ in 0..<100 where release==nil{await Task.yield()}
        let continuation=try XCTUnwrap(release)
        XCTAssertFalse(completed)
        continuation.resume();await finish.value
        XCTAssertTrue(completed);XCTAssertNil(manager.backgroundCompletion)
    }
}
