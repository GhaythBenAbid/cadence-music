import XCTest
@testable import CadenceCore

private final class DiscoveryProtocol:URLProtocol,@unchecked Sendable {
    static var handler:((URLRequest)throws->(Int,String))?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){do{let (status,body)=try Self.handler!(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
    override func stopLoading(){}
}
private final class DiscoveryVault:DiscoverySessionVault,@unchecked Sendable {
    private let lock=NSLock();private var values:[String:Data]=[:]
    func load(_ key:String)->Data?{lock.lock();defer{lock.unlock()};return values[key]}
    func save(_ data:Data?,key:String){lock.lock();defer{lock.unlock()};values[key]=data}
    var count:Int{lock.lock();defer{lock.unlock()};return values.count}
}
final class DiscoveryTests:XCTestCase {
    func testSpotifyLinksAcceptOnlyPlaylistIDs(){
        let id="37i9dQZF1DZ06evNZVVBPG"
        for link in ["https://open.spotify.com/playlist/"+id+"?si=tracking", "spotify:playlist:"+id, "https://open.spotify.com/intl-fr/playlist/"+id]{XCTAssertEqual(SpotifyPlaylistLink.id(link),id)}
        for link in ["https://open.spotify.com.evil.test/playlist/"+id,"https://user:password@open.spotify.com/playlist/"+id,"http://open.spotify.com/playlist/"+id,"https://open.spotify.com/track/"+id,"https://spotify.link/short","spotify:playlist:../private","https://open.spotify.com/playlist/"+id+"/extra"]{XCTAssertNil(SpotifyPlaylistLink.id(link))}
    }
    func testSpotifyImportContractAndProgressDoNotTurnPendingMetadataIntoAudio()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DiscoveryProtocol.self]
        var mutations=0
        DiscoveryProtocol.handler={request in
            switch request.url!.path{
            case "/api/auth/login":return(200,"{\"token\":\"fixture\",\"expiresAt\":\(Date().addingTimeInterval(3600).timeIntervalSince1970*1000)}")
            case "/api/playlists/import/spotify/status":return(200,#"{"connected":true,"reconnectRequired":false}"#)
            case "/api/playlists/import/spotify/preview":XCTAssertEqual(request.httpMethod,"POST");return(200,#"{"trackCount":50,"skipped":2,"previewTracks":[{"trackName":"A song","artistName":"Artist"}]}"#)
            case "/api/playlists/import/spotify":
                mutations+=1;XCTAssertEqual(request.httpMethod,"POST");XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture")
                // URLProtocol can expose the POST body as a stream; inspect through either representation.
                var data=request.httpBody ?? Data()
                if let stream=request.httpBodyStream{stream.open();defer{stream.close()};var bytes=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable{let n=stream.read(&bytes,maxLength:bytes.count);if n<=0{break};data.append(contentsOf:bytes.prefix(n))}}
                let body=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                XCTAssertEqual(body["playlistId"] as? String,"37i9dQZF1DZ06evNZVVBPG");XCTAssertEqual(body["name"] as? String,"My picks");XCTAssertEqual(body["syncEnabled"] as? Bool,true);XCTAssertEqual(body["syncIntervalHours"] as? Int,24);XCTAssertEqual(body["keepRemovedTracks"] as? Bool,true)
                return(200,#"{"success":true,"playlist":null,"tracksQueued":50,"tracksReused":0,"queued":true}"#)
            case "/api/playlists/status":return(200,#"{"sharedPlaylists":[{"id":"abc-123","name":"My picks","trackCount":50,"importSource":{"provider":"spotify-playlist","syncEnabled":true}}],"sharedPlaylistStats":{"abc-123":{"total":50,"pending":44,"downloading":1,"blocked":1,"done":3,"failed":1}}}"#)
            default:XCTFail("Unexpected request");return(404,"{}")
            }
        };defer{DiscoveryProtocol.handler=nil}
        let api=AurralDiscoveryAPI(credentials:ServerCredentials(server:URL(string:"https://example.test")!,username:"fixture",password:"fixture"),session:URLSession(configuration:config))
        let connected=try await api.spotifyConnection();XCTAssertTrue(connected.connected)
        let preview=try await api.previewSpotify(link:"spotify:playlist:37i9dQZF1DZ06evNZVVBPG");XCTAssertEqual(preview.trackCount,50)
        let receipt=try await api.importSpotify(link:"spotify:playlist:37i9dQZF1DZ06evNZVVBPG",name:"  My picks  ",sync:true);XCTAssertEqual(receipt.tracksQueued,50);XCTAssertEqual(mutations,1)
        let status=try await api.importStatus();XCTAssertEqual(status.spotifyPlaylists.first?.subsonicID,"shared:abc-123");XCTAssertEqual(status.sharedPlaylistStats["abc-123"]?.done,3)
    }
    func testSpotifyExpiredConnectionAndAmbiguousMutationNeverAutomaticallyRetry()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DiscoveryProtocol.self]
        var attempts=0,failCode=401
        DiscoveryProtocol.handler={request in
            if request.url!.path=="/api/auth/login"{return(200,"{\"token\":\"fixture\",\"expiresAt\":\(Date().addingTimeInterval(3600).timeIntervalSince1970*1000)}")}
            attempts+=1;return(failCode,#"{"code":"SPOTIFY_AUTH_REQUIRED"}"#)
        };defer{DiscoveryProtocol.handler=nil}
        let api=AurralDiscoveryAPI(credentials:ServerCredentials(server:URL(string:"https://example.test")!,username:"fixture",password:"fixture"),session:URLSession(configuration:config))
        do{_=try await api.importSpotify(link:"spotify:playlist:37i9dQZF1DZ06evNZVVBPG",name:"Picks",sync:false);XCTFail("Must require connection")}catch SpotifyImportError.connect{};XCTAssertEqual(attempts,1)
        failCode=502
        do{_=try await api.importSpotify(link:"spotify:playlist:37i9dQZF1DZ06evNZVVBPG",name:"Picks",sync:false);XCTFail("Must report uncertain result")}catch SpotifyImportError.uncertain{};XCTAssertEqual(attempts,2)
        failCode=403
        do{_=try await api.previewSpotify(link:"spotify:playlist:37i9dQZF1DZ06evNZVVBPG");XCTFail("Must distinguish Spotify access from Aurral permissions")}catch SpotifyImportError.playlistAccess{};XCTAssertEqual(attempts,3)
        do{_=try await api.spotifyConnection();XCTFail("Must respect permissions")}catch SpotifyImportError.permission{};XCTAssertEqual(attempts,4)
    }
    func testEditorialAndArtistTracksDecodeWithoutTurningPreviewsIntoLibrarySongs()throws{
        let editorial=try JSONDecoder().decode(DiscoverTrack.self,from:Data(#"{"artistName":"Artist","trackName":"New song","albumName":"New album","durationMs":204000,"preview_url":"/api/deezer/preview/1.mp3"}"#.utf8))
        XCTAssertEqual(editorial.title,"New song");XCTAssertEqual(editorial.album,"New album");XCTAssertEqual(editorial.durationMS,204000)
        let again=try JSONDecoder().decode(DiscoverTrack.self,from:JSONEncoder().encode(editorial));XCTAssertEqual(editorial.id,again.id)
        XCTAssertNil(DiscoveryLinks.libraryMatch(editorial,artist:"Artist",songs:[Song(id:"wrong",title:"New song",artist:"Other artist")]))
        let owned=Song(id:"owned",title:"New song",artist:"Artist");XCTAssertEqual(DiscoveryLinks.libraryMatch(editorial,artist:"Artist",songs:[owned])?.id,"owned")
    }
    func testReleaseDatesAndUnreadStateRoundTrip()throws{
        let now=Date(timeIntervalSince1970:1793836800)
        let release=DiscoverRelease(id:"new",albumName:"Tomorrow",artistName:"Artist",releaseDate:"2099-01-01")
        XCTAssertTrue(release.upcoming(now:now));XCTAssertNil(DiscoverRelease(id:"bad",albumName:"Bad",artistName:"A",releaseDate:"2026-02-30").date)
        XCTAssertFalse(DiscoverRelease(id:"year",albumName:"Year",artistName:"A",releaseDate:"2026").upcoming(now:now))
        var snapshot=DiscoverSnapshot(response:DiscoverResponse(),releases:[release]);XCTAssertEqual(snapshot.newCount,1)
        snapshot.seenReleaseIDs=[release.id];let saved=try JSONDecoder().decode(DiscoverSnapshot.self,from:JSONEncoder().encode(snapshot));XCTAssertEqual(saved.newCount,0)
    }
    func testSafeMediaURLsAndArtistLinks(){
        let server=URL(string:"https://music.example:8443")!
        XCTAssertEqual(DiscoveryLinks.media("/api/deezer/preview/1.mp3",server:server)?.host,"music.example")
        for value in ["http://other.example/a","file:///private/a","javascript:alert(1)","https://user:secret@other.example/a"]{XCTAssertNil(DiscoveryLinks.media(value,server:server))}
        let artist=DiscoverArtist(name:"A & B/../C");let link=DiscoveryLinks.artist(artist,server:server)
        XCTAssertEqual(link.path,"/search");XCTAssertEqual(URLComponents(url:link,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,artist.name)
    }
    func testSparseArtistPayloadHasHonestRecommendationReason()throws{
        let artist=try JSONDecoder().decode(DiscoverArtist.self,from:Data(#"{"id":null,"name":"New artist","image":null,"sourceArtists":["Favorite artist"]}"#.utf8))
        XCTAssertEqual(artist.reason,"Because you like Favorite artist");XCTAssertEqual(artist.id,"new artist")
    }
    func testScopedAuthenticationReusesVaultAndRenewsOnceAfter401()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DiscoveryProtocol.self]
        let network=URLSession(configuration:config),vault=DiscoveryVault()
        let credentials=ServerCredentials(server:URL(string:"https://music.example")!,username:"fixture",password:"fixture")
        var logins=0,discoveries=0,rejectNext=false
        DiscoveryProtocol.handler={request in
            XCTAssertFalse(request.url!.absoluteString.contains("fixture"));XCTAssertNil(request.url?.user);XCTAssertNil(request.url?.password)
            switch request.url!.path{
            case "/api/health/bootstrap":return(200,#"{"api":{"version":1,"features":["discover"]}}"#)
            case "/api/auth/login":
                logins+=1;XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));return(200,"{\"token\":\"fixture-\(logins)\",\"expiresAt\":\(Date().addingTimeInterval(3600).timeIntervalSince1970*1000)}")
            case "/api/discover":
                discoveries+=1
                if rejectNext{rejectNext=false;return(401,"{}")}
                XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture-\(logins)")
                return(200,#"{"recommendations":[{"id":null,"name":"Discovery"}],"globalTop":[],"configured":true}"#)
            case "/api/library/recent-releases":return(200,"[]")
            case "/api/discover/editorial":return(200,#"{"forYou":[]}"#)
            case "/api/auth/logout":return(200,"{}")
            default:XCTFail("Unexpected API path");return(404,"{}")
            }
        };defer{DiscoveryProtocol.handler=nil}
        let first=AurralDiscoveryAPI(credentials:credentials,session:network,vault:vault)
        let feed=try await first.feed();XCTAssertEqual(feed.response.recommendations.first?.name,"Discovery");XCTAssertEqual(logins,1);XCTAssertEqual(vault.count,1)
        let relaunched=AurralDiscoveryAPI(credentials:credentials,session:network,vault:vault)
        _=try await relaunched.feed();XCTAssertEqual(logins,1)
        rejectNext=true;_=try await relaunched.feed();XCTAssertEqual(logins,2);XCTAssertEqual(discoveries,4)
        let changed=AurralDiscoveryAPI(credentials:ServerCredentials(server:credentials.server,username:credentials.username,password:"new-fixture"),session:network,vault:vault)
        _=try await changed.feed();XCTAssertEqual(logins,3);XCTAssertEqual(vault.count,2)
        await changed.signOut();XCTAssertEqual(vault.count,1)
        await relaunched.signOut();XCTAssertEqual(vault.count,0)
    }
    func testMissingCapabilityDoesNotAttemptPasswordLogin()async throws{
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DiscoveryProtocol.self]
        var calls=0;DiscoveryProtocol.handler={request in calls+=1;XCTAssertEqual(request.url?.path,"/api/health/bootstrap");return(200,#"{"api":{"version":1,"features":[]}}"#)};defer{DiscoveryProtocol.handler=nil}
        let api=AurralDiscoveryAPI(credentials:ServerCredentials(server:URL(string:"https://example.test")!,username:"fixture",password:"fixture"),session:URLSession(configuration:config))
        do{_=try await api.feed();XCTFail("Must not use an unadvertised discovery API")}catch{XCTAssertTrue(error is DiscoveryAPIError)};XCTAssertEqual(calls,1)
    }
}
