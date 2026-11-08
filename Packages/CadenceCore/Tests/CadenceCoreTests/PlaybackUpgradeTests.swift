import XCTest
@testable import CadenceCore

final class PlaybackUpgradeTests:XCTestCase {
    let song=Song(id:"fixture",title:"Fixture",artist:"Artist")
    func testLegacySnapshotAndNewRepeatModeAreCompatible()throws{
        let old=PlaybackSnapshot(queue:PlaybackQueue(songs:[song]),position:8,repeats:true,volume:0.3)
        var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as! [String:Any]
        json.removeValue(forKey:"repeatMode");json.removeValue(forKey:"autoplay")
        let decoded=try JSONDecoder().decode(PlaybackSnapshot.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertTrue(decoded.repeats);XCTAssertNil(decoded.repeatMode);try decoded.validate()
        let upgraded=PlaybackSnapshot(queue:old.queue,position:8,repeats:true,volume:0.3,repeatMode:.one,autoplay:true)
        let roundtrip=try JSONDecoder().decode(PlaybackSnapshot.self,from:JSONEncoder().encode(upgraded))
        XCTAssertEqual(roundtrip.repeatMode,.one);XCTAssertEqual(roundtrip.queue.entries.first?.id,old.queue.entries.first?.id)
    }
    func testAutoplayHistoryTrimmingPreservesCurrentAndDuplicateEntries()throws{
        var queue=PlaybackQueue(songs:Array(repeating:song,count:1000))
        for _ in 0..<999{XCTAssertTrue(queue.advance(repeating:false))}
        let current=queue.current?.id;queue.trimHistory(keeping:100);queue.append(Song(id:"next",title:"Next"))
        try queue.validate();XCTAssertEqual(queue.current?.id,current);XCTAssertEqual(queue.entries.count,102)
        XCTAssertTrue(queue.advance(repeating:false));XCTAssertEqual(queue.current?.song.id,"next")
    }
    func testSearchPagesRequestExactlyOneKindAndKeepOffsets(){
        let params=Dictionary(uniqueKeysWithValues:SearchKind.artists.parameters(offset:30,size:30).map{($0.name,$0.value!)})
        XCTAssertEqual(params["artistCount"],"30");XCTAssertEqual(params["artistOffset"],"30");XCTAssertEqual(params["songCount"],"0");XCTAssertEqual(params["albumCount"],"0")
    }
    func testTransferValidationAndIdempotency()throws{
        var queue=PlaybackQueue(songs:[song,song]);_=queue.advance(repeating:false)
        let snapshot=PlaybackSnapshot(queue:queue,position:12,repeats:false,volume:0.3,repeatMode:.off)
        try PlaybackTransfer(.toMac,snapshot:snapshot).validate()
        XCTAssertThrowsError(try PlaybackTransfer(.toMac).validate())
        XCTAssertThrowsError(try PlaybackTransfer(.toPhone,snapshot:snapshot).validate())
        var request=MacRemoteRequest();request.transfer=PlaybackTransfer(.toMac,snapshot:snapshot)
        var replay=MacRemoteReplayGuard(),effects=0
        func action()->MacRemoteResponse{effects+=1;var r=MacRemoteResponse(id:request.id);r.transfer=TransferredPlayback(snapshot:snapshot,play:true);return r}
        _=try replay.executeTransfer(request,action:action);let response=try replay.executeTransfer(request,action:action)
        XCTAssertEqual(effects,1);XCTAssertEqual(response.transfer?.snapshot.queue.entries.map(\.id),queue.entries.map(\.id));XCTAssertEqual(response.transfer?.snapshot.position,12)
        request.command=PhoneCommand(.next);XCTAssertThrowsError(try request.validate())
    }
    func testNewProtocolStillDecodesLegacyControlRequests()throws{
        let old=MacRemoteRequest(command:PhoneCommand(.pause))
        let data=try JSONEncoder().encode(old),decoded=try JSONDecoder().decode(MacRemoteRequest.self,from:data)
        XCTAssertNil(decoded.transfer);XCTAssertNil(decoded.acceptsHandoff);try decoded.validate()
        let legacy=MacRemoteResponse(id:decoded.id,playback:PhonePlayback(song:nil,isPlaying:false,elapsed:0,duration:0,shuffled:false,repeats:false,volume:1))
        let reply=try JSONDecoder().decode(MacRemoteResponse.self,from:JSONEncoder().encode(legacy));XCTAssertNil(reply.capabilities)
    }
}
