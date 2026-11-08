import XCTest
import CadenceCore
@testable import Cadence

@MainActor private final class TransferFixture:WatchMixSending {
    var canTransfer=true
    var receipt:WatchReceipt?
    var sent:[TrackTransfer]=[]
    var pending:Set<String>=[]
    func sendMix(_ mix:RunMix)throws{}
    func sendFile(_ file:URL,payload:TrackTransfer)throws{try FileIntegrity.verify(file,transfer:payload);sent.append(payload);pending.insert(payload.songID)}
    func outstandingSongIDs(for mix:RunMix)->Set<String>{pending}
    func cancelOutstanding(){pending=[]}
    func resetReceipt(){receipt=nil}
}

final class WatchPreparationTests:XCTestCase {
    @MainActor func testPersistentPlanContinuesWhenDownloadsArriveAndDeduplicatesQueuedFiles()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let preferences=UserDefaults(suiteName:UUID().uuidString)!,transport=TransferFixture()
        let local=LocalLibrary(root:root.appendingPathComponent("audio"),preferences:preferences)
        var sources:[String:URL]=[:],requested:[Song]=[]
        let songs=Array(DemoLibrary.songs.prefix(2))
        var preparation:WatchPreparation?=WatchPreparation(local:local,transport:transport,root:root.appendingPathComponent("plan"),available:{sources[$0.id]},requestDownloads:{requested += $0})
        try preparation!.start(name:"Background run",songs:songs,account:"cadence-demo")
        await preparation!.flush();XCTAssertEqual(Set(requested.map(\.id)),Set(songs.map(\.id)));XCTAssertTrue(transport.sent.isEmpty)
        preparation=nil // Simulate an OS termination, retaining the durable plan.
        let restored=WatchPreparation(local:local,transport:transport,root:root.appendingPathComponent("plan"),available:{sources[$0.id]},requestDownloads:{requested += $0})
        restored.configure(account:"cadence-demo")
        sources[songs[0].id]=try XCTUnwrap(DemoLibrary.url(songs[0]))
        await restored.flush();XCTAssertEqual(transport.sent.map(\.songID),[songs[0].id])
        sources[songs[1].id]=try XCTUnwrap(DemoLibrary.url(songs[1]))
        await restored.flush();XCTAssertEqual(transport.sent.map(\.songID),songs.map(\.id))
        await restored.flush(reconcile:true);XCTAssertEqual(transport.sent.count,2)
        XCTAssertTrue(restored.active) // Queued is not yet confirmed saved on Watch.
        restored.receive(WatchReceipt(mixID:try XCTUnwrap(restored.plan?.mix.id),accountKey:"cadence-demo",readyIDs:songs.map(\.id)))
        XCTAssertFalse(restored.active)
        let again=WatchPreparation(local:local,transport:transport,root:root.appendingPathComponent("plan"),available:{sources[$0.id]},requestDownloads:{_ in})
        XCTAssertNil(again.plan)
    }
    @MainActor func testCancelDuringHashCannotQueueOldAccountFile()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let local=LocalLibrary(root:root.appendingPathComponent("audio"),preferences:UserDefaults(suiteName:UUID().uuidString)!),transport=TransferFixture(),song=DemoLibrary.songs[0]
        var release:CheckedContinuation<Void,Never>?
        let preparation=WatchPreparation(local:local,transport:transport,root:root.appendingPathComponent("plan"),available:{DemoLibrary.url($0)},requestDownloads:{_ in},digest:{url in await withCheckedContinuation{release=$0};return try FileIntegrity.sha256(url)})
        try preparation.start(name:"Cancel",songs:[song],account:"cadence-demo")
        let flush=Task{await preparation.flush()}
        for _ in 0..<100 where release==nil{await Task.yield()}
        let continuation=try XCTUnwrap(release)
        preparation.configure(account:String(repeating:"a",count:64));continuation.resume();await flush.value
        XCTAssertNil(preparation.plan);XCTAssertTrue(transport.sent.isEmpty)
    }
}

@MainActor private final class MultipleMixFixture:WatchMixSending {
    var canTransfer=true
    var supportsMultipleMixes=true
    var receipt:WatchReceipt?
    var known:[String:WatchReceipt]=[:]
    func receipt(for mix:RunMix)->WatchReceipt?{known[mix.id]}
    func sendMix(_ mix:RunMix)throws{}
    func sendFile(_ file:URL,payload:TrackTransfer)throws{}
    func cancelOutstanding(){}
    func resetReceipt(){receipt=nil}
    func outstandingSongIDs(for mix:RunMix)->Set<String>{[]}
}
extension WatchPreparationTests {
    @MainActor func testResendingKnownPlaylistPreservesIDButErasedPlaylistGetsFreshManifest()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let local=LocalLibrary(root:root.appendingPathComponent("local"),preferences:UserDefaults(suiteName:UUID().uuidString)!),transport=MultipleMixFixture(),song=DemoLibrary.songs[0]
        let prep=WatchPreparation(local:local,transport:transport,root:root.appendingPathComponent("plan"),available:{DemoLibrary.url($0)},requestDownloads:{_ in})
        try prep.start(name:"One",songs:[song],account:"cadence-demo");let first=try XCTUnwrap(local.mix);transport.known[first.id]=WatchReceipt(mixID:first.id,accountKey:first.accountKey,readyIDs:[song.id])
        try prep.start(name:first.name,songs:first.songs,account:first.accountKey,existing:first);XCTAssertEqual(local.mix?.id,first.id);XCTAssertEqual(local.mixes.count,1)
        transport.known=[:]
        try prep.start(name:first.name,songs:first.songs,account:first.accountKey,existing:first);XCTAssertNotEqual(local.mix?.id,first.id);XCTAssertEqual(local.mixes.count,1)
        prep.cancel()
    }
}
