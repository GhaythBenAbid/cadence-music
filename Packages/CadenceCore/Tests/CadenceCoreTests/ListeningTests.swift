import XCTest
@testable import CadenceCore

final class ListeningTests:XCTestCase {
    let songs=(0..<5).map{Song(id:String($0),title:"Song \($0)",artist:$0<2 ? "A" : "B",duration:120)}
    func testQueuePreservesDuplicateTracksAndFutureEdits()throws{
        var queue=PlaybackQueue(songs:[songs[0],songs[0],songs[1]])
        XCTAssertNotEqual(queue.entries[0].id,queue.entries[1].id)
        queue.append(songs[2],next:true);XCTAssertEqual(queue.upcoming.first?.song.id,"2")
        queue.moveUpcoming(from:0,to:2);XCTAssertEqual(queue.upcoming.last?.song.id,"2")
        queue.removeUpcoming(queue.current!.id);XCTAssertEqual(queue.entries.count,4)
        queue.removeUpcoming(queue.upcoming[0].id);XCTAssertEqual(queue.entries.count,3)
        XCTAssertTrue(queue.advance(repeating:false));XCTAssertEqual(queue.current?.song.id,"1")
        queue.clearUpcoming();XCTAssertFalse(queue.advance(repeating:false));XCTAssertTrue(queue.advance(repeating:true));XCTAssertEqual(queue.current?.song.id,"0")
        try queue.validate()
    }
    func testShuffleRetainsCurrentAndRestoresUnplayedOrder()throws{
        var queue=PlaybackQueue(songs:songs,startingAt:songs[1]);let current=queue.current
        queue.toggleShuffle();XCTAssertEqual(queue.current,current);XCTAssertEqual(Set(queue.entries.map(\.song.id)),Set(songs.map(\.id)))
        queue.append(songs[0]);queue.toggleShuffle();XCTAssertEqual(queue.upcoming.map(\.song.id),["2","3","4","0"])
        try queue.validate()
    }
    func testSessionRestoresPositionAndSeparatesAccounts()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=PlaybackSessionStore(root:root);let queue=PlaybackQueue(songs:songs)
        try store.save(PlaybackSnapshot(queue:queue,position:42,repeats:false,volume:0.4),account:"alice")
        XCTAssertEqual(store.load(account:"alice")?.position,42);XCTAssertEqual(store.load(account:"alice")?.queue,queue);XCTAssertNil(store.load(account:"bob"))
        XCTAssertThrowsError(try store.save(PlaybackSnapshot(queue:queue,position:.infinity,repeats:false,volume:1),account:"alice"))
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil);XCTAssertFalse(files[0].lastPathComponent.contains("alice"))
        store.clear(account:"alice");XCTAssertNil(store.load(account:"alice"))
    }
    func testDiscoveryExcludesSeedAndDeduplicatesRelatedFavorites(){
        let result=LibraryDiscovery.mix(random:[songs[3],songs[1],songs[1],songs[0]],favorites:[songs[0]],seed:songs[0])
        XCTAssertEqual(result.map(\.id),["1","3"])
    }
    func testLegacyPlaylistPayloadStillDecodes()throws{
        let playlist=try JSONDecoder().decode(Playlist.self,from:Data(#"{"id":"old","name":"Old playlist","songCount":2}"#.utf8));XCTAssertNil(playlist.owner);XCTAssertNil(playlist.entry)
    }
}

private final class PlaylistProtocol:URLProtocol,@unchecked Sendable {
    static var handler:((URLRequest)throws->Data)?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){do{let data=try Self.handler!(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
    override func stopLoading(){}
}
final class PlaylistContractTests:XCTestCase {
    func testEditReplacesInOrderAndRefusesStaleBaseline()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[PlaylistProtocol.self]
        let api=SubsonicAPI(credentials:ServerCredentials(server:URL(string:"https://example.test")!,username:"fixture",password:"fixture"),session:URLSession(configuration:config))
        let a=Song(id:"a",title:"A"),b=Song(id:"b",title:"B");var original=Playlist(id:"p",name:"Before");original.entry=[a,b]
        var calls=0
        PlaylistProtocol.handler={request in
            calls+=1
            if request.url!.lastPathComponent=="getPlaylist.view"{return Data(#"{"subsonic-response":{"status":"ok","playlist":{"id":"p","name":"Before","entry":[{"id":"a","title":"A"},{"id":"b","title":"B"}]}}}"#.utf8)}
            XCTAssertEqual(request.url!.lastPathComponent,"updatePlaylist.view")
            var body=request.httpBody ?? Data()
            if let stream=request.httpBodyStream{stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable{let count=stream.read(&buffer,maxLength:buffer.count);guard count>0 else{break};body.append(buffer,count:count)}}
            var parts=URLComponents();parts.percentEncodedQuery=String(data:body,encoding:.utf8)
            let items=parts.queryItems!;XCTAssertEqual(items.filter{$0.name=="songIndexToRemove"}.compactMap(\.value),["1","0"]);XCTAssertEqual(items.filter{$0.name=="songIdToAdd"}.compactMap(\.value),["b","a","b"])
            return Data(#"{"subsonic-response":{"status":"ok"}}"#.utf8)
        }
        defer{PlaylistProtocol.handler=nil}
        try await api.editPlaylist(original,name:"After",songs:[b,a,b]);XCTAssertEqual(calls,2)
        original.entry=[b,a]
        do{try await api.editPlaylist(original,name:"Stale",songs:[a]);XCTFail("Must reject edits made against an old playlist")}catch{}
        XCTAssertEqual(calls,3)
    }
}
