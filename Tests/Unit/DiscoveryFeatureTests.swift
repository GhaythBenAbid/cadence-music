import XCTest
import AVFoundation
import CadenceCore
@testable import Cadence

final class DiscoveryFeatureTests:XCTestCase {
    @MainActor func testImportRefreshFailureIsVisibleAndConnectionFailureDoesNotHidePlaylists()async throws{
        let state=SpotifyImportState()
        let connection=try JSONDecoder().decode(SpotifyConnection.self,from:Data(#"{"connected":true}"#.utf8))
        let imports=try JSONDecoder().decode(PlaylistImportStatus.self,from:Data(#"{"sharedPlaylists":[{"id":"test","name":"Imported picks","trackCount":1,"importSource":{"provider":"spotify-playlist","syncEnabled":false}}],"sharedPlaylistStats":{}}"#.utf8))
        await state.reload(connection:{connection},imports:{imports})
        await state.reload(quiet:true,connection:{connection},imports:{throw SpotifyImportError.unavailable})
        XCTAssertNotNil(state.statusError,"A failed automatic refresh must be visible, not an empty/unchanging screen")
        XCTAssertEqual(state.status?.spotifyPlaylists.count,1,"Keep the last successful result")
        state.reset()
        await state.reload(connection:{throw SpotifyImportError.connect},imports:{imports})
        XCTAssertNotNil(state.connectionError)
        XCTAssertEqual(state.status?.spotifyPlaylists.count,1,"Existing imports remain available when Spotify needs reconnecting")
    }
    @MainActor func testImportReceiptSurvivesSheetLifetimeButClearsWithAccount(){
        let model=DiscoveryModel();model.configure(nil,demo:true)
        model.imports.acceptedName="My playlist";model.imports.acceptedCount=50
        let reopened=model.imports;XCTAssertEqual(reopened.acceptedCount,50)
        model.configure(ServerCredentials(server:URL(string:"https://example.test")!,username:"other",password:"fixture"))
        XCTAssertNil(reopened.acceptedName);XCTAssertNil(reopened.status);XCTAssertNil(reopened.connection)
    }
    @MainActor func testDemoDiscoveryAndFullPlaybackStaySeparate()async throws{
        let store=PhoneStore();store.enterDemo();store.audio.stop();store.prepareAudio();defer{store.audio.stop();store.discover.preview.stop()}
        XCTAssertEqual(store.discover.newCount,2);store.discover.markSeen();XCTAssertEqual(store.discover.newCount,0)
        let track=DiscoveryModel.demoTracks[0],url=try XCTUnwrap(store.discover.previewURL(track))
        store.discover.preview.toggle(id:track.id,url:url,beforePlay:{store.audio.pause()})
        XCTAssertEqual(store.discover.preview.currentID,track.id);XCTAssertNil(store.audio.current)
        let played=try await store.playDiscovery(track,artist:"Cadence Sessions")
        XCTAssertTrue(played);XCTAssertNil(store.discover.preview.currentID);XCTAssertEqual(store.audio.current?.id,DemoLibrary.songs[0].id)
        let missing=DiscoverTrack(id:"metadata-only",title:"Not in this library",artistName:"Other artist")
        let absent=try await store.playDiscovery(missing,artist:"Other artist");XCTAssertFalse(absent)
    }
    @MainActor func testDiscoverySwitchClearsOldProfileAndPreview(){
        let model=DiscoveryModel();model.configure(nil,demo:true);XCTAssertNotNil(model.snapshot)
        model.configure(ServerCredentials(server:URL(string:"https://example.test")!,username:"other",password:"fixture"))
        XCTAssertNil(model.snapshot);XCTAssertFalse(model.isDemo);XCTAssertNil(model.preview.currentID);XCTAssertEqual(model.newCount,0)
        model.configure(nil);XCTAssertNil(model.server)
    }
    @MainActor func testOptionalLiveSpotifyStatusAndReadyPlayback()async throws{
        struct Fixture:Decodable{var url:String;var username:String;var password:String;var playlistName:String?;var playlistLink:String?}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLiveSpotifyFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires a private local Spotify fixture.")};try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data),server=try ServerCredentials.normalizedServer(fixture.url)
        let credentials=ServerCredentials(server:server,username:fixture.username,password:fixture.password),client=AurralDiscoveryAPI(credentials:credentials)
        do{
            let connection=try await client.spotifyConnection();XCTAssertTrue(connection.connected)
            if let link=fixture.playlistLink{let preview=try await client.previewSpotify(link:link);XCTAssertGreaterThan(preview.trackCount,0)}
            let status=try await client.importStatus();XCTAssertFalse(status.spotifyPlaylists.isEmpty)
            let ready=try XCTUnwrap(status.spotifyPlaylists.first{(status.sharedPlaylistStats[$0.id]?.done ?? 0)>0 && (fixture.playlistName==nil || $0.name==fixture.playlistName)})
            let playlist=try await SubsonicAPI(credentials:credentials).playlist(ready.subsonicID)
            let song=try XCTUnwrap(playlist.entry?.first)
            let asset=AVURLAsset(url:SubsonicAPI(credentials:credentials).authenticatedURL("stream",parameters:[.init(name:"id",value:song.id)])),playable=try await asset.load(.isPlayable)
            let duration=try await asset.load(.duration);XCTAssertTrue(playable);XCTAssertGreaterThan(duration.seconds,30);await client.signOut()
        }catch{await client.signOut();throw error}
    }
    @MainActor func testOptionalLiveDiscoveryAndPreview()async throws{
        struct Fixture:Decodable{var url:String;var username:String;var password:String}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLiveDiscoveryFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires a private local discovery fixture.")};try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data),server=try ServerCredentials.normalizedServer(fixture.url)
        let client=AurralDiscoveryAPI(credentials:ServerCredentials(server:server,username:fixture.username,password:fixture.password))
        do{
            let feed=try await client.feed();XCTAssertFalse(feed.response.recommendations.isEmpty);XCTAssertFalse(feed.response.globalTop.isEmpty)
            XCTAssertTrue((feed.partialSources ?? []).isEmpty)
            let artist=try XCTUnwrap(feed.response.recommendations.first),tracks=try await client.artistTracks(artist)
            let track=try XCTUnwrap(tracks.first),url=try XCTUnwrap(DiscoveryLinks.media(track.previewURL,server:server))
            let asset=AVURLAsset(url:url),playable=try await asset.load(.isPlayable),duration=try await asset.load(.duration)
            XCTAssertTrue(playable);XCTAssertGreaterThan(duration.seconds,0);XCTAssertLessThanOrEqual(duration.seconds,31)
            if let playlist=feed.playlists.first{let full=try await client.playlist(playlist);XCTAssertFalse(full.tracks.isEmpty);XCTAssertFalse(full.tracks[0].title.isEmpty)}
            await client.signOut()
        }catch{await client.signOut();throw error}
    }
}
