import XCTest
@testable import CadenceCore

final class BackgroundDeliveryTests:XCTestCase {
    @MainActor func testWakeWaitsForActivationPendingContentAndQueuedImport(){
        let activity=TransferActivity()
        var wrongCompletion=false
        let unactivated=BackgroundDeliveryGate(activity:activity);unactivated.hold{wrongCompletion=true};unactivated.refresh(activated:false,contentPending:false);XCTAssertFalse(wrongCompletion)
        let real=BackgroundDeliveryGate(activity:activity)
        // The file callback has run, but its MainActor import hasn't started yet.
        let ticket=activity.begin();var completions=0
        real.hold{completions+=1};real.hold{completions+=1}
        real.refresh(activated:true,contentPending:false);XCTAssertEqual(completions,0)
        activity.end(ticket);real.refresh(activated:true,contentPending:true);XCTAssertEqual(completions,0)
        real.refresh(activated:true,contentPending:false);XCTAssertEqual(completions,2)
        real.refresh(activated:true,contentPending:false);XCTAssertEqual(completions,2)
    }
    @MainActor func testExpirationCompletesOnlyExpiredWakeAndKeepsImportTracked(){
        let activity=TransferActivity()
        let real=BackgroundDeliveryGate(activity:activity),ticket=activity.begin();var expired=0,finished=0
        let first=real.hold{expired+=1};real.hold{finished+=1}
        real.expire(first);real.expire(first);XCTAssertEqual(expired,1);XCTAssertEqual(finished,0);XCTAssertTrue(activity.hasWork)
        activity.end(ticket);activity.end(ticket);XCTAssertFalse(activity.hasWork)
        real.refresh(activated:true,contentPending:false);XCTAssertEqual(finished,1)
    }
    func testPlanPersistsQueueAndRejectsForeignTrackIDs()throws{
        let mix=try RunMix(accountKey:"cadence-demo",name:"Run",songs:[Song(id:"one",title:"One")])
        var plan=WatchPreparationPlan(mix:mix);plan.scheduledIDs=["one"]
        let saved=try JSONDecoder().decode(WatchPreparationPlan.self,from:JSONEncoder().encode(plan));try saved.validate();XCTAssertEqual(saved.scheduledIDs,["one"])
        plan.scheduledIDs.insert("foreign");XCTAssertThrowsError(try plan.validate())
    }
}

extension BackgroundDeliveryTests {
    func testExpirationCancelsCurrentImportsButNewWakeCanStartFresh(){
        let activity=TransferActivity(),old=activity.begin();XCTAssertFalse(activity.isCancelled(old))
        activity.cancelAll();XCTAssertTrue(activity.isCancelled(old));XCTAssertTrue(activity.hasWork)
        let next=activity.begin();XCTAssertFalse(activity.isCancelled(next))
        activity.end(old);XCTAssertTrue(activity.hasWork);activity.end(next);XCTAssertFalse(activity.hasWork)
    }
}

extension BackgroundDeliveryTests {
    func testFileVerificationCanStopBetweenChunksWithoutDeletingStagedFile()throws{
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:file)}
        try Data(repeating:1,count:600_000).write(to:file)
        var checks=0
        XCTAssertThrowsError(try FileIntegrity.sha256(file,shouldContinue:{checks+=1;return checks<3})){XCTAssertTrue($0 is CancellationError)}
        XCTAssertEqual(checks,3);XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
        XCTAssertEqual(try FileIntegrity.sha256(file).count,64)
    }
}
