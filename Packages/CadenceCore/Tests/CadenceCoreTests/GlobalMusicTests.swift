import XCTest
@testable import CadenceCore

private final class GlobalProtocol:URLProtocol,@unchecked Sendable {
    static var handler:((URLRequest)throws->(Int,String))?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){do{let(status,body)=try Self.handler!(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
    override func stopLoading(){}
}
final class GlobalMusicTests:XCTestCase {
    func testGlobalMetadataIsSeparateFromPlayableSongsAndFiltersOtherMedia()throws{
        let response=try JSONDecoder().decode(MusicCatalogResponse.self,from:Data(#"{"results":[{"wrapperType":"track","kind":"song","trackId":7,"trackName":"Beyond","artistName":"Artist","previewUrl":"https://example.test/preview"},{"kind":"music-video","trackId":8,"trackName":"Video","artistName":"Artist"},{"kind":"song","trackId":7,"trackName":"Beyond","artistName":"Artist"},{"wrapperType":"artist","artistId":9,"artistName":"Artist"}]}"#.utf8))
        let tracks=response.entries(.song);XCTAssertEqual(tracks.count,1);XCTAssertEqual(tracks.first?.id,"7");XCTAssertEqual(response.entries(.artist).count,1)
        let track=try XCTUnwrap(tracks.first)
        XCTAssertNil(track.libraryMatch([Song(id:"wrong",title:"Beyond",artist:"Other")]))
        XCTAssertEqual(track.libraryMatch([Song(id:"owned",title:"BEYOND",artist:"Artist")])?.id,"owned")
        XCTAssertNil(MusicCatalogEntry(id:"bad",kind:.song,title:"X",artist:"Y",storeURL:"https://music.apple.com.evil.test/").link)
    }
    func testGlobalSearchUsesPublicMetadataWithoutMusicCredentialsAndCaches()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[GlobalProtocol.self];var calls=0
        GlobalProtocol.handler={request in calls+=1;XCTAssertEqual(request.url?.host,"itunes.apple.com");XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!;XCTAssertEqual(query.first{$0.name=="term"}?.value,"Artist & Song");XCTAssertEqual(query.first{$0.name=="entity"}?.value,"song");return(200,#"{"results":[{"kind":"song","trackId":1,"trackName":"Song","artistName":"Artist"}]}"#)}
        defer{GlobalProtocol.handler=nil};let api=GlobalMusicAPI(session:URLSession(configuration:config));let first=try await api.search("Artist & Song",kind:.songs),second=try await api.search("Artist & Song",kind:.songs);XCTAssertEqual(first,second);XCTAssertEqual(calls,1)
    }
    func testPreparationContractAndAmbiguousRequestsNeverRetry()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[GlobalProtocol.self];var calls=0,code=202
        GlobalProtocol.handler={request in
            if request.url!.path=="/api/auth/login"{return(200,"{\"token\":\"fixture\",\"expiresAt\":\(Date().addingTimeInterval(3600).timeIntervalSince1970*1000)}")}
            if request.url!.path=="/api/playlists/jobs"{return(200,#"[{"id":"job","status":"downloading","progress":50}]"#)}
            calls+=1;XCTAssertEqual(request.url!.path,"/api/library/downloads/track");XCTAssertEqual(request.httpMethod,"POST");XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture")
            var data=request.httpBody ?? Data();if let stream=request.httpBodyStream{stream.open();defer{stream.close()};var bytes=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable{let n=stream.read(&bytes,maxLength:bytes.count);if n<=0{break};data.append(contentsOf:bytes.prefix(n))}}
            let body=try JSONSerialization.jsonObject(with:data) as! [String:Any];XCTAssertEqual(body["trackName"] as? String,"Song");XCTAssertEqual(body["artistName"] as? String,"Artist");XCTAssertNil(body["previewUrl"])
            return(code,#"{"success":true,"jobId":"job","queued":true}"#)
        };defer{GlobalProtocol.handler=nil}
        let api=AurralDiscoveryAPI(credentials:ServerCredentials(server:URL(string:"https://fixture.test")!,username:"fixture",password:"fixture"),session:URLSession(configuration:config)),track=MusicCatalogEntry(id:"1",kind:.song,title:"Song",artist:"Artist")
        let receipt=try await api.prepareTrack(track);XCTAssertEqual(receipt.jobId,"job");XCTAssertEqual(calls,1)
        let jobs=try await api.preparationJobs();XCTAssertEqual(jobs.first?.status,"downloading")
        code=502;do{_=try await api.prepareTrack(track);XCTFail("Must report an unconfirmed mutation")}catch GlobalMusicError.uncertain{};XCTAssertEqual(calls,2)
        code=403;do{_=try await api.prepareTrack(track);XCTFail("Must respect account permissions")}catch GlobalMusicError.permission{};XCTAssertEqual(calls,3)
    }
}
