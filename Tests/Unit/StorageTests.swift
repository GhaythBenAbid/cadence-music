import XCTest
import CadenceCore
@testable import Cadence
final class StorageTests:XCTestCase{
    @MainActor private func library() throws -> LocalLibrary{
        let id=UUID().uuidString
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let defaults=UserDefaults(suiteName:id)!
        addTeardownBlock{try? FileManager.default.removeItem(at:root);UserDefaults.standard.removePersistentDomain(forName:id)}
        return LocalLibrary(root:root,preferences:defaults)
    }
    private func account(_ user:String)->String{ServerCredentials(server:URL(string:"https://music.example")!,username:user,password:"fixture").accountKey}
    private func file(_ data:Data)throws->URL{let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try data.write(to:url);return url}
    @MainActor func testVerifiedTransferIsAcknowledgedOnlyAfterSave()async throws{
        let library=try library(), song=Song(id:"track",title:"Run")
        let mix=try RunMix(accountKey:account("one"),name:"Run",songs:[song])
        var receipt:WatchReceipt?
        library.onReceipt={receipt=$0};try library.accept(mix)
        XCTAssertEqual(receipt?.readyIDs,[])
        let source=try file(Data("original audio".utf8))
        let payload=TrackTransfer(mix:mix,songID:song.id,bytes:14,sha256:try FileIntegrity.sha256(source))
        await library.receive(source,payload:payload)
        XCTAssertEqual(receipt?.readyIDs,["track"]);XCTAssertNotNil(library.localURL(song));XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
    }
    @MainActor func testCorruptedTransferCannotBecomeReady()async throws{
        let library=try library(),song=Song(id:"track",title:"Run")
        let mix=try RunMix(accountKey:account("one"),name:"Run",songs:[song]);try library.accept(mix)
        let source=try file(Data("damaged".utf8))
        await library.receive(source,payload:TrackTransfer(mix:mix,songID:song.id,bytes:14,sha256:String(repeating:"0",count:64)))
        XCTAssertTrue(library.readyIDs.isEmpty);XCTAssertNotNil(library.message);XCTAssertNil(library.localURL(song))
    }
    @MainActor func testAccountSwitchRejectsDelayedOldFiles()async throws{
        let library=try library(),song=Song(id:"track",title:"Run")
        let old=try RunMix(accountKey:account("one"),name:"Old",songs:[song],createdAt:Date(timeIntervalSince1970:1000))
        try library.accept(old);let source=try file(Data("old audio".utf8));_=try library.cache(source,song:song,account:old.accountKey)
        let newer=try RunMix(accountKey:account("two"),name:"New",songs:[song],createdAt:Date(timeIntervalSince1970:2000));try library.accept(newer)
        XCTAssertTrue(library.readyIDs.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:library.url(for:song,account:old.accountKey).path))
        let delayed=try file(Data("old audio".utf8));let payload=TrackTransfer(mix:old,songID:song.id,bytes:9,sha256:try FileIntegrity.sha256(delayed))
        await library.receive(delayed,payload:payload)
        XCTAssertEqual(library.mix?.accountKey,newer.accountKey);XCTAssertTrue(library.readyIDs.isEmpty)
    }
    @MainActor func testStaleEraseCannotClearNewMixAndErasedMixCannotReplay()async throws{
        let library=try library(),song=Song(id:"track",title:"Run")
        let mix=try RunMix(accountKey:account("one"),name:"New",songs:[song],createdAt:Date(timeIntervalSince1970:2000));try library.accept(mix)
        XCTAssertFalse(library.clear(at:Date(timeIntervalSince1970:1500)));XCTAssertEqual(library.mix?.id,mix.id)
        var receipt:WatchReceipt?;library.onReceipt={receipt=$0}
        XCTAssertTrue(library.clear(at:Date(timeIntervalSince1970:2500)));XCTAssertNil(library.mix)
        XCTAssertEqual(receipt?.mixID,mix.id);XCTAssertEqual(receipt?.readyIDs,[])
        XCTAssertThrowsError(try library.accept(mix))
    }
}

extension StorageTests {
    @MainActor func testExpiredBackgroundImportKeepsStagedAudioForNextWake()async throws{
        let library=try library(),song=Song(id:"track",title:"Run")
        let mix=try RunMix(accountKey:account("one"),name:"Run",songs:[song]);try library.accept(mix)
        let source=try file(Data("original audio".utf8))
        let payload=TrackTransfer(mix:mix,songID:song.id,bytes:14,sha256:try FileIntegrity.sha256(source))
        await library.receive(source,payload:payload,shouldContinue:{false})
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path));XCTAssertTrue(library.readyIDs.isEmpty)
        await library.receive(source,payload:payload)
        XCTAssertEqual(library.readyIDs,[song.id]);XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
    }
}
