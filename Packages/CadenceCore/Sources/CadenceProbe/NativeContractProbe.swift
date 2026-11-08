import Foundation
import AVFoundation
import CryptoKit
import CadenceCore

/// Explicitly opted-in integration check against an isolated loopback Aurral instance.
@MainActor enum NativeContractProbe {
    private struct Fixture:Decodable {
        var server:String;var username:String;var password:String
        var expectedAPIVersion:Int;var playlistName:String;var trackTitle:String;var artist:String
        var sha256:String;var allowOwnedPreparation:Bool
    }
    static func run()async throws{
        guard let path=ProcessInfo.processInfo.environment["CADENCE_CONTRACT_FIXTURE"] else{throw CadenceError.message("Set CADENCE_CONTRACT_FIXTURE to a private local fixture file.")}
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        guard let parts=URLComponents(string:fixture.server),["http","https"].contains(parts.scheme ?? ""),["127.0.0.1","::1","[::1]"].contains(parts.host ?? ""),parts.port != nil,parts.user==nil,parts.password==nil,parts.query==nil,parts.fragment==nil,let server=parts.url else{throw CadenceError.message("Contract checks require an explicitly configured loopback server.")}
        let credentials=ServerCredentials(server:server,username:fixture.username,password:fixture.password)
        let api=SubsonicAPI(credentials:credentials),native=AurralDiscoveryAPI(credentials:credentials)
        let (bootstrap,response)=try await URLSession.shared.data(from:server.appendingPathComponent("api/health/bootstrap"))
        let json=try JSONSerialization.jsonObject(with:bootstrap) as? [String:Any]
        guard (response as? HTTPURLResponse)?.statusCode==200,(json?["api"] as? [String:Any])?["version"] as? Int==fixture.expectedAPIVersion else{throw CadenceError.message("The isolated provider has an unexpected API version.")}
        let feed=try await native.feed()
        guard !(feed.partialSources ?? []).contains("playlists") else{throw CadenceError.message("The real provider playlist shelf did not complete.")}
        print("PASS: real native API bootstrap, authentication, Discover and playlist shelf")
        let status=try await native.importStatus()
        guard let playlist=status.spotifyPlaylists.first(where:{$0.name==fixture.playlistName}),(status.sharedPlaylistStats[playlist.id]?.done ?? 0)>0 else{throw CadenceError.message("The isolated imported-playlist fixture is not ready.")}
        try await api.ping()
        let songs=try await api.playlist(playlist.subsonicID).entry ?? []
        guard let song=songs.first(where:{$0.title==fixture.trackTitle && $0.artist==fixture.artist}) else{throw CadenceError.message("The fixture playlist did not resolve through Subsonic.")}
        print("PASS: current import status decodes and the retained Subsonic playlist ID resolves")
        if fixture.allowOwnedPreparation{
            let entry=MusicCatalogEntry(id:"fixture",kind:.song,title:fixture.trackTitle,artist:fixture.artist,album:song.album)
            let receipt=try await native.prepareTrack(entry)
            guard receipt.success,receipt.alreadyOwned==true else{throw CadenceError.message("The provider did not reuse the existing owned track.")}
            print("PASS: owned preparation returns alreadyOwned without acquiring music")
        }
        _=try await native.preparationJobs()
        let file=try await api.download(song);defer{try? FileManager.default.removeItem(at:file)}
        let data=try Data(contentsOf:file),digest=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        guard digest==fixture.sha256 else{throw CadenceError.message("Downloaded audio differs from the complete original fixture.")}
        let stream=api.authenticatedURL("stream",parameters:[.init(name:"id",value:song.id)])
        let asset=AVURLAsset(url:stream)
        guard try await asset.load(.isPlayable),try await asset.load(.duration).seconds>=55 else{throw CadenceError.message("The full fixture stream is not playable.")}
        let player=AVPlayer(playerItem:AVPlayerItem(asset:asset));player.volume=0;player.play();defer{player.pause()}
        for _ in 0..<100 where player.currentTime().seconds<0.5{try await Task.sleep(for:.milliseconds(100))}
        guard player.currentTime().seconds>0.4 else{throw CadenceError.message("The authenticated full-audio timeline did not advance.")}
        await native.signOut()
        print("PASS: complete original-file checksum, full stream duration and actual AVFoundation playback")
    }
}
