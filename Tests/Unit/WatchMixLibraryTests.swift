import XCTest
import CadenceCore
@testable import Cadence

@MainActor final class WatchMixLibraryTests:XCTestCase {
    private func library()throws->LocalLibrary{let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);addTeardownBlock{try? FileManager.default.removeItem(at:root)};return LocalLibrary(root:root,preferences:UserDefaults(suiteName:UUID().uuidString)!,pruneUnused:true)}
    private func mix(_ id:String,songs:[Song],time:Double=1000)throws->RunMix{var value=try RunMix(id:id,accountKey:"cadence-demo",name:id,songs:songs,createdAt:Date(timeIntervalSince1970:time));value.keepOtherMixes=true;return value}
    private func cache(_ local:LocalLibrary,_ song:Song)throws{let source=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try Data("audio".utf8).write(to:source);_=try local.cache(source,song:song,account:"cadence-demo")}
    func testMultiplePlaylistsSurviveRestartAndSharedAudioIsNotRemoved()throws{
        let local=try library(),shared=Song(id:"shared",title:"Shared"),one=Song(id:"one",title:"One"),two=Song(id:"two",title:"Two")
        let a=try mix("a",songs:[shared,one]),b=try mix("b",songs:[shared,two],time:2000)
        try local.accept(a);try cache(local,shared);try cache(local,one);try local.accept(b);try cache(local,two)
        XCTAssertEqual(local.mixes.count,2);XCTAssertEqual(local.mix?.id,"a","Background receipt must not interrupt the selected playlist")
        try local.select("b");XCTAssertEqual(local.readyIDs,Set([shared.id,two.id]))
        let restored=LocalLibrary(root:local.root,preferences:UserDefaults(suiteName:UUID().uuidString)!,pruneUnused:true);XCTAssertEqual(restored.mixes.count,2);XCTAssertEqual(restored.mix?.id,"b")
        XCTAssertTrue(try restored.remove(WatchMixRemoval(a,removedAt:Date(timeIntervalSince1970:3000))));XCTAssertNotNil(restored.localURL(shared));XCTAssertNil(restored.localURL(one));XCTAssertNotNil(restored.localURL(two));XCTAssertThrowsError(try restored.accept(a))
    }
    func testLegacyMigrationAndLegacySenderRetainSingleMixSemantics()throws{
        let local=try library(),song=Song(id:"song",title:"Song"),old=try RunMix(accountKey:"cadence-demo",name:"Legacy",songs:[song],createdAt:Date(timeIntervalSince1970:1000))
        try JSONEncoder().encode(old).write(to:local.root.appendingPathComponent("mix.json"));let migrated=LocalLibrary(root:local.root,preferences:UserDefaults(suiteName:UUID().uuidString)!);XCTAssertEqual(migrated.mixes.map(\.id),[old.id])
        let second=try mix("second",songs:[song],time:2000);try migrated.accept(second);XCTAssertEqual(migrated.mixes.count,2)
        let legacy=try RunMix(accountKey:"cadence-demo",name:"Old phone",songs:[song],createdAt:Date(timeIntervalSince1970:3000));try migrated.accept(legacy);XCTAssertEqual(migrated.mixes.count,1)
    }
    func testLateFilesCannotResurrectDeletedMixOrOldAccount()async throws{
        let local=try library(),song=Song(id:"song",title:"Song"),a=try mix("a",songs:[song])
        try local.accept(a);_=try local.remove(WatchMixRemoval(a,removedAt:Date(timeIntervalSince1970:2000)))
        let source=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try Data("audio".utf8).write(to:source);let payload=TrackTransfer(mix:a,songID:song.id,bytes:5,sha256:try FileIntegrity.sha256(source));await local.receive(source,payload:payload);XCTAssertTrue(local.mixes.isEmpty)
        var newer=try RunMix(accountKey:String(repeating:"a",count:64),name:"New account",songs:[song],createdAt:Date(timeIntervalSince1970:4000));newer.keepOtherMixes=true;try local.accept(newer);XCTAssertThrowsError(try local.accept(a));XCTAssertEqual(local.mixes.count,1)
    }
}

extension WatchMixLibraryTests {
    func testUnreadableNewerIndexCannotEraseExistingAudio()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)};try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let bytes=Data("{\"version\":99,\"mixes\":[]}".utf8);try bytes.write(to:root.appendingPathComponent("mixes.json"))
        let local=LocalLibrary(root:root,preferences:UserDefaults(suiteName:UUID().uuidString)!,pruneUnused:true),song=Song(id:"song",title:"Song")
        XCTAssertThrowsError(try local.accept(RunMix(accountKey:"cadence-demo",name:"Incoming",songs:[song])));XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("mixes.json")),bytes)
    }
}
