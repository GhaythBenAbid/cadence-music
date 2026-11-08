import XCTest
@testable import CadenceCore

private final class VersionedProtocol:URLProtocol,@unchecked Sendable {
    static var handler:((URLRequest)throws->(Int,String))?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        do{
            let (status,body)=try Self.handler!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
        }catch{client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading(){}
}
final class APIV2Tests:XCTestCase {
    private func api()->AurralDiscoveryAPI{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[VersionedProtocol.self]
        return AurralDiscoveryAPI(credentials:ServerCredentials(server:URL(string:"https://fixture.test")!,username:"fixture",password:"fixture"),session:URLSession(configuration:config))
    }
    private var login:String{"{\"token\":\"fixture\",\"expiresAt\":\(Date().addingTimeInterval(3600).timeIntervalSince1970*1000)}"}
    override func tearDown(){VersionedProtocol.handler=nil;super.tearDown()}

    func testV2BaselineWithEmptyFeaturesLoadsNewShelfAndProviderDetails()async throws{
        var paths=[String]();let lock=NSLock();let login=self.login
        VersionedProtocol.handler={request in
            let path=request.url!.path;lock.lock();paths.append(path);lock.unlock()
            if path=="/api/health/bootstrap"{XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));return(200,#"{"api":{"version":2,"features":[]},"future":true}"#)}
            if path=="/api/auth/login"{return(200,login)}
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture")
            switch path{
            case "/api/discover":return(200,#"{"recommendations":[{"id":null,"name":"Artist","type":"artist","tags":[],"image":null}],"globalTop":[],"basedOn":[],"topTags":[],"topGenres":[],"configured":false,"provider":"fixture","lastUpdated":null}"#)
            case "/api/library/recent-releases":return(200,"[]")
            case "/api/discover/playlists":return(200,#"{"forYou":[{"provider":"deezer","id":"7","name":"Picks","trackCount":1,"artworkUrl":null,"curator":null},{"provider":"mix","id":"7","name":"Mix"},{"provider":"discovery","id":"new-to-you","name":"Discover"},{"provider":"future","id":"7","name":"Unknown"},{"provider":"mix","id":"../private","name":"Unsafe"}],"categories":[]}"#)
            case "/api/discover/playlists/deezer/7", "/api/discover/playlists/mix/7", "/api/discover/playlists/discovery/new-to-you":return(200,#"{"tracks":[{"trackName":"Original track","artistName":"Artist","albumName":"Original album","durationMs":120000,"preview_url":null,"owned":{"id":3}}]}"#)
            default:XCTFail("Unexpected route: "+path);return(404,"{}")
            }
        }
        let client=api(),snapshot=try await client.feed()
        XCTAssertEqual(snapshot.playlists.map(\.listID),["deezer:7","mix:7","discovery:new-to-you"])
        XCTAssertEqual(snapshot.response.recommendations.first?.name,"Artist");XCTAssertEqual(snapshot.partialSources,[])
        for playlist in snapshot.playlists{let detail=try await client.playlist(playlist);XCTAssertEqual(detail.tracks.first?.title,"Original track");XCTAssertNil(detail.tracks.first?.previewURL)}
        XCTAssertFalse(paths.contains("/api/discover/editorial"))
        XCTAssertEqual(paths.filter{$0=="/api/health/bootstrap"}.count,1)
    }
    func testV1AndV2AreRenegotiatedWhenDiscoverRefreshes()async throws{
        var version=1,paths=[String]();let lock=NSLock();let login=self.login
        VersionedProtocol.handler={request in
            let path=request.url!.path;lock.lock();paths.append(path);lock.unlock()
            switch path{
            case "/api/health/bootstrap":return(200,version==1 ? #"{"api":{"version":1,"features":["discover"]}}"# : #"{"api":{"version":2,"features":["future"]}}"#)
            case "/api/auth/login":return(200,login)
            case "/api/discover":return(200,#"{"recommendations":[],"globalTop":[]}"#)
            case "/api/library/recent-releases":return(200,"[]")
            case "/api/discover/editorial", "/api/discover/playlists":return(200,#"{"forYou":[{"id":"7","name":"Picks"}]}"#)
            case "/api/discover/editorial/7", "/api/discover/playlists/deezer/7":return(200,#"{"tracks":[]}"#)
            default:XCTFail("Unexpected route");return(404,"{}")
            }
        }
        let client=api();let old=try await client.feed();_=try await client.playlist(XCTUnwrap(old.playlists.first));version=2
        let new=try await client.feed();_=try await client.playlist(XCTUnwrap(new.playlists.first))
        XCTAssertTrue(paths.contains("/api/discover/editorial/7"));XCTAssertTrue(paths.contains("/api/discover/playlists/deezer/7"))
        XCTAssertEqual(paths.filter{$0=="/api/auth/login"}.count,1)
    }
    func testUnknownContractAndMissingV1CapabilityDoNotAuthenticate()async throws{
        for bootstrap in [#"{"api":{"version":3,"features":["discover"]}}"#,#"{"api":{"version":1,"features":[]}}"#,#"{"api":null}"#]{
            var requests=0
            VersionedProtocol.handler={request in requests+=1;XCTAssertEqual(request.url?.path,"/api/health/bootstrap");return(200,bootstrap)}
            do{_=try await api().feed();XCTFail("Unsupported contract must fail")}catch DiscoveryAPIError.unsupported{}
            XCTAssertEqual(requests,1)
        }
    }
    func testMalformedV2BootstrapAndUnsafePlaylistCannotReachAuthenticatedRoute()async throws{
        for bootstrap in [#"{"api":{"version":"2","features":[]}}"#,#"{"api":{"version":2}}"#,#"{"api":{"version":2,"features":null}}"#]{
            VersionedProtocol.handler={request in XCTAssertEqual(request.url?.path,"/api/health/bootstrap");return(200,bootstrap)}
            do{_=try await api().feed();XCTFail("Malformed contract must fail")}catch is DecodingError{}
        }
        VersionedProtocol.handler={_ in XCTFail("Unsafe ID must not make a request");return(404,"{}")}
        do{_=try await api().playlist(DiscoverPlaylist(id:"../secret",name:"Unsafe",provider:"mix"));XCTFail()}catch DiscoveryAPIError.unavailable{}
    }
    func testV2PartialSourcesAndPermissionErrorsStayVisible()async throws{
        var forbidden=false;let login=self.login
        VersionedProtocol.handler={request in
            switch request.url!.path{
            case "/api/health/bootstrap":return(200,#"{"api":{"version":2,"features":[]}}"#)
            case "/api/auth/login":return(200,login)
            case "/api/discover":return forbidden ? (403,#"{"error":"Forbidden"}"#) : (200,#"{"recommendations":[],"globalTop":[]}"#)
            case "/api/library/recent-releases":return(503,#"{"error":"Unavailable"}"#)
            case "/api/discover/playlists":return(200,#"{"forYou":[],"categories":[]}"#)
            default:XCTFail();return(404,"{}")
            }
        }
        let client=api();let value=try await client.feed();XCTAssertEqual(value.partialSources,["releases"])
        forbidden=true;do{_=try await client.feed();XCTFail()}catch DiscoveryAPIError.permission{}
    }
    func testV2ImportStatusKeepsSubsonicSharedIDsAndUsesCurrentFields()throws{
        let json=#"{"staticPlaylists":[{"id":"new-picks","name":"New picks","trackCount":1,"importSource":{"provider":"spotify-playlist","syncEnabled":true}}],"staticPlaylistStats":{"new-picks":{"total":1,"pending":0,"downloading":0,"blocked":0,"done":1,"failed":0}},"sharedPlaylists":[],"sharedPlaylistStats":{}}"#
        let value=try JSONDecoder().decode(PlaylistImportStatus.self,from:Data(json.utf8))
        XCTAssertEqual(value.spotifyPlaylists.first?.subsonicID,"shared:new-picks")
        XCTAssertEqual(value.sharedPlaylistStats["new-picks"]?.done,1)
        let empty=try JSONDecoder().decode(PlaylistImportStatus.self,from:Data(#"{"staticPlaylists":[],"staticPlaylistStats":{}}"#.utf8));XCTAssertTrue(empty.spotifyPlaylists.isEmpty)
        for bad in [#"{}"#,#"{"staticPlaylists":null,"staticPlaylistStats":{}}"#,#"{"staticPlaylists":[],"staticPlaylistStats":[]}"#]{XCTAssertThrowsError(try JSONDecoder().decode(PlaylistImportStatus.self,from:Data(bad.utf8)))}
    }
}
