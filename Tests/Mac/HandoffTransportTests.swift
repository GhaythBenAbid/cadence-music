import XCTest
import CadenceCore

@MainActor final class HandoffTransportTests:XCTestCase {
    func testEncryptedLiveQueueTransferAndRetryDoNotRepeatPlayback()async throws{
        let preferences=try XCTUnwrap(UserDefaults(suiteName:"handoff-test-"+UUID().uuidString))
        let credentials=ServerCredentials(server:URL(string:"https://fixture.invalid")!,username:"fixture",password:"fixture")
        let server=PrivateMacServer(port:47824,preferences:preferences,advertise:false)
        server.configure(credentials);defer{server.stop()}
        for _ in 0..<40 where server.endpoint==nil{try await Task.sleep(for:.milliseconds(50))}
        guard let endpoint=server.endpoint else{throw XCTSkip("A private Tailscale interface is required for this isolated live transport check.")}
        let song=Song(id:"fixture",title:"Fixture",artist:"Cadence")
        var snapshot=PlaybackSnapshot(queue:PlaybackQueue(songs:[song,song]),position:9,repeats:true,volume:0.3,repeatMode:.one,autoplay:false)
        var macPlaying=false,imports=0,exports=0
        server.playback={PhonePlayback(song:snapshot.queue.current?.song,isPlaying:macPlaying,elapsed:snapshot.position,duration:120,shuffled:false,repeats:true,volume:0.3)}
        server.transfer={transfer in
            switch transfer.direction{
            case .toMac:imports+=1;snapshot=try XCTUnwrap(transfer.snapshot);macPlaying=transfer.play;return TransferredPlayback(snapshot:snapshot,play:macPlaying)
            case .toPhone:exports+=1;let wasPlaying=macPlaying;macPlaying=false;return TransferredPlayback(snapshot:snapshot,play:wasPlaying)
            case .editQueue:snapshot=try XCTUnwrap(transfer.snapshot);return TransferredPlayback(snapshot:snapshot,play:macPlaying)
            case .inspect:return TransferredPlayback(snapshot:snapshot,play:macPlaying)
            }
        }
        let client=PrivateMacClient(preferences:preferences);client.configure(credentials);try client.select(endpoint)
        let id=UUID().uuidString
        _=try await client.transfer(PlaybackTransfer(.toMac,snapshot:snapshot,play:true),id:id)
        _=try await client.transfer(PlaybackTransfer(.toMac,snapshot:snapshot,play:true),id:id)
        XCTAssertEqual(imports,1);XCTAssertTrue(macPlaying)
        let pullID=UUID().uuidString,result=try await client.transfer(PlaybackTransfer(.toPhone),id:pullID)
        let again=try await client.transfer(PlaybackTransfer(.toPhone),id:pullID)
        XCTAssertFalse(macPlaying);XCTAssertEqual(exports,1);XCTAssertTrue(result.play);XCTAssertTrue(again.play)
        XCTAssertEqual(result.snapshot.queue.entries.map(\.id),snapshot.queue.entries.map(\.id));XCTAssertEqual(result.snapshot.position,9);XCTAssertEqual(result.snapshot.repeatMode,.one)
        _=try await client.poll(phonePlayback:PhonePlayback(song:song,isPlaying:true,elapsed:9,duration:120,shuffled:false,repeats:true,volume:0.3))
        XCTAssertTrue(server.phoneAvailable)
        let instruction=PhoneInstruction(.continueOnMac);try server.instructPhone(instruction)
        let pending=try await client.poll(phonePlayback:PhonePlayback(song:song,isPlaying:true,elapsed:10,duration:120,shuffled:false,repeats:true,volume:0.3))
        XCTAssertEqual(pending.instruction?.id,instruction.id)
        _=try await client.poll(phonePlayback:PhonePlayback(song:song,isPlaying:true,elapsed:10,duration:120,shuffled:false,repeats:true,volume:0.3),acknowledged:instruction.id)
        XCTAssertNil(server.pendingInstruction);XCTAssertEqual(server.lastAcknowledgedInstructionID,instruction.id)
        let handoff=PhoneInstruction(.continueOnPhone);try server.instructPhone(handoff)
        _=try await client.transfer(PlaybackTransfer(.toPhone),id:handoff.id)
        XCTAssertNil(server.pendingInstruction)
        let followup=PhoneInstruction(.command,command:PhoneCommand(.pause));try server.instructPhone(followup)
        _=try await client.poll(phonePlayback:PhonePlayback(song:song,isPlaying:true,elapsed:10,duration:120,shuffled:false,repeats:true,volume:0.3),acknowledged:handoff.id)
        XCTAssertEqual(server.lastAcknowledgedInstructionID,handoff.id,"A completed handoff must still accept the phone's final acknowledgment")
        XCTAssertEqual(server.pendingInstruction?.id,followup.id,"A late handoff acknowledgment cannot erase a newer command")
        // An older control-only Mac must receive a small status request, not a large phone heartbeat.
        server.transfer=nil
        let legacy=PrivateMacClient(preferences:UserDefaults(suiteName:"legacy-handoff-"+UUID().uuidString)!);legacy.configure(credentials);try legacy.select(endpoint)
        server.configure(credentials);server.playback={PhonePlayback(song:nil,isPlaying:false,elapsed:0,duration:0,shuffled:false,repeats:false,volume:1)}
        for _ in 0..<40 where server.endpoint==nil{try await Task.sleep(for:.milliseconds(50))}
        _=try await legacy.poll(phonePlayback:PhonePlayback(song:song,isPlaying:true,elapsed:0,duration:120,shuffled:false,repeats:false,volume:1))
        XCTAssertFalse(server.phoneAvailable)
        let wrong=PrivateMacClient(preferences:UserDefaults(suiteName:"wrong-handoff-"+UUID().uuidString)!);wrong.configure(ServerCredentials(server:credentials.server,username:"other",password:"wrong"));try wrong.select(endpoint)
        do{_=try await wrong.fetch();XCTFail("Another account must not read the queue")}catch{}
    }
}
