#if os(iOS) || os(macOS)
import Foundation
import SwiftUI
import AVFoundation
import Security
import CadenceCore

struct DiscoveryKeychain:DiscoverySessionVault {
    private let service="com.bahachammakhi.cadence.discovery.session"
    func load(_ key:String)->Data?{
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var value:CFTypeRef?;guard SecItemCopyMatching(query as CFDictionary,&value)==errSecSuccess else{return nil};return value as? Data
    }
    func save(_ data:Data?,key:String){
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key]
        guard let data else{SecItemDelete(query as CFDictionary);return}
        let values:[String:Any]=[kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary,values as CFDictionary)==errSecItemNotFound{var add=query;values.forEach{add[$0.key]=$0.value};SecItemAdd(add as CFDictionary,nil)}
    }
}

@MainActor final class DiscoveryPreview:ObservableObject {
    @Published private(set) var currentID:String?
    @Published private(set) var error:String?
    private let player=AVPlayer()
    private var end:NSObjectProtocol?
    private var observation:NSKeyValueObservation?
    #if os(iOS)
    private let session=AVAudioSession.sharedInstance()
    #endif
    init(){end=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main){[weak self] note in Task{@MainActor in guard let self,let item=note.object as? AVPlayerItem,self.player.currentItem===item else{return};self.stop()}}}
    func toggle(id:String,url:URL?,beforePlay:()->Void){
        if currentID==id{stop();return}
        guard let url,url.scheme=="https" || url.isFileURL else{error="A preview isn't available for this song.";return}
        beforePlay();error=nil
        do{
            #if os(iOS)
            try session.setCategory(.playback,mode:.default);try session.setActive(true)
            #endif
            let item=AVPlayerItem(url:url);item.forwardPlaybackEndTime=CMTime(seconds:30,preferredTimescale:600);observation=item.observe(\.status,options:[.new]){[weak self] item,_ in Task{@MainActor in guard let self,self.player.currentItem===item,item.status == .failed else{return};self.stop();self.error="This preview is temporarily unavailable."}}
            player.replaceCurrentItem(with:item);currentID=id;player.play()
        }catch{self.error="The audio preview couldn't start."}
    }
    func stop(){player.pause();player.replaceCurrentItem(with:nil);observation=nil;currentID=nil}
}

@MainActor final class DiscoveryModel:ObservableObject {
    @Published private(set) var snapshot:DiscoverSnapshot?
    @Published private(set) var loading=false
    @Published private(set) var error:String?
    @Published private(set) var isDemo=false
    let preview=DiscoveryPreview()
    let imports=SpotifyImportState()
    private(set) var server:URL?
    private var account:String?
    private var identity:ServerCredentials?
    private var api:AurralDiscoveryAPI?
    private var generation=UUID()
    private let root:URL
    var newCount:Int{snapshot?.newCount ?? 0}
    init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceDiscovery",isDirectory:true)}
    private var file:URL?{account.map{root.appendingPathComponent($0+".json")}}
    func configure(_ credentials:ServerCredentials?,demo:Bool=false){
        guard credentials != identity || demo != isDemo else{return}
        generation=UUID();imports.reset();preview.stop();identity=credentials;isDemo=demo;server=credentials?.server;account=credentials?.accountKey;loading=false;error=nil;snapshot=nil
        api=credentials.map{AurralDiscoveryAPI(credentials:$0,vault:DiscoveryKeychain())}
        if demo{snapshot=Self.demo();return}
        if let file,let data=try? Data(contentsOf:file){snapshot=try? JSONDecoder().decode(DiscoverSnapshot.self,from:data)}
    }
    func refresh(force:Bool=false)async{
        guard !isDemo,!loading,let api else{return}
        if !force,let snapshot,Date().timeIntervalSince(snapshot.savedAt)<1800{return}
        let stamp=generation;loading=true;error=nil
        do{var fresh=try await api.feed();guard generation==stamp else{return};fresh.seenReleaseIDs=snapshot?.seenReleaseIDs ?? [];if fresh.partialSources?.contains("releases")==true{fresh.releases=snapshot?.releases ?? []};if fresh.partialSources?.contains("playlists")==true{fresh.playlists=snapshot?.playlists ?? []};snapshot=fresh;if !(fresh.partialSources ?? []).isEmpty{error="Some discovery sections couldn’t refresh. Saved items are shown where available."};save()}
        catch{if generation==stamp{self.error=snapshot==nil ? ((error as? DiscoveryAPIError)?.localizedDescription ?? "Discover couldn’t load. Check your server connection and try again.") : "Showing saved discoveries. Refresh when connected."}}
        if generation==stamp{loading=false}
    }
    func markSeen(){guard var value=snapshot else{return};value.seenReleaseIDs.formUnion(value.releases.map(\.id));snapshot=value;save()}
    private func save(){guard let file,let snapshot else{return};try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try? JSONEncoder().encode(snapshot).write(to:file,options:.atomic)}
    func tracks(artist:DiscoverArtist)async throws->[DiscoverTrack]{if isDemo{return Self.demoTracks};guard let api else{return []};let stamp=generation;let value=try await api.artistTracks(artist);guard generation==stamp else{throw CancellationError()};return value}
    func tracks(playlist:DiscoverPlaylist)async throws->[DiscoverTrack]{if isDemo{return Self.demoTracks};guard let api else{return []};let stamp=generation;let value=try await api.playlist(playlist).tracks;guard generation==stamp else{throw CancellationError()};return value}
    func previewURL(_ track:DiscoverTrack)->URL?{if isDemo{return DemoLibrary.songs.first{$0.title==track.title}.flatMap{DemoLibrary.url($0)}};return server.flatMap{DiscoveryLinks.media(track.previewURL,server:$0)}}
    var accountName:String{identity?.username ?? "Demo"}
    var profileID:String{account ?? (isDemo ? "demo" : "signed-out")}
    func spotifyConnection()async throws->SpotifyConnection {
        if isDemo{return try JSONDecoder().decode(SpotifyConnection.self,from:Data(#"{"connected":true}"#.utf8))}
        guard let api else{throw SpotifyImportError.unavailable};let stamp=generation;let result=try await api.spotifyConnection();guard stamp==generation else{throw CancellationError()};return result
    }
    func spotifyPreview(_ link:String)async throws->SpotifyImportPreview {
        guard SpotifyPlaylistLink.id(link) != nil else{throw SpotifyImportError.invalidLink}
        if isDemo{return try JSONDecoder().decode(SpotifyImportPreview.self,from:Data(#"{"trackCount":3,"skipped":0,"previewTracks":[{"artistName":"Cadence Sessions","trackName":"First Light"},{"artistName":"Cadence Sessions","trackName":"Homeward"},{"artistName":"Cadence Sessions","trackName":"Blue Hour"}]}"#.utf8))}
        guard let api else{throw SpotifyImportError.unavailable};let stamp=generation;let result=try await api.previewSpotify(link:link);guard stamp==generation else{throw CancellationError()};return result
    }
    func importSpotify(_ link:String,name:String,sync:Bool)async throws->SpotifyImportReceipt {
        guard !isDemo,let api else{throw SpotifyImportError.unavailable};let stamp=generation;let result=try await api.importSpotify(link:link,name:name,sync:sync);guard stamp==generation else{throw CancellationError()};return result
    }
    func spotifyImports()async throws->PlaylistImportStatus {
        if isDemo{return try JSONDecoder().decode(PlaylistImportStatus.self,from:Data(#"{"sharedPlaylists":[{"id":"demo-import","name":"Demo Spotify picks","trackCount":3,"importSource":{"provider":"spotify-playlist","syncEnabled":false}}],"sharedPlaylistStats":{"demo-import":{"total":3,"pending":0,"downloading":0,"blocked":0,"done":3,"failed":0}}}"#.utf8))}
        guard let api else{throw SpotifyImportError.unavailable};let stamp=generation;let result=try await api.importStatus();guard stamp==generation else{throw CancellationError()};return result
    }
    func globalSearch(_ query:String,kind:SearchKind)async throws->[MusicCatalogEntry]{
        if isDemo{return Self.demoCatalog.filter{kind == .songs ? $0.kind == .song : kind == .artists ? $0.kind == .artist : $0.kind == .album}.filter{($0.title+" "+$0.artist).localizedCaseInsensitiveContains(query)}}
        let stamp=generation;let result=try await GlobalMusicAPI.shared.search(query,kind:kind);guard stamp==generation else{throw CancellationError()};return result
    }
    func globalChildren(_ entry:MusicCatalogEntry)async throws->[MusicCatalogEntry]{
        if isDemo{return Self.demoCatalog.filter{entry.kind == .artist ? $0.kind == .album : $0.kind == .song}}
        let stamp=generation;let result=try await GlobalMusicAPI.shared.children(entry);guard stamp==generation else{throw CancellationError()};return result
    }
    func prepareTrack(_ entry:MusicCatalogEntry)async throws->TrackPreparationReceipt{guard !isDemo,let api else{throw GlobalMusicError.unavailable};let stamp=generation;let value=try await api.prepareTrack(entry);guard stamp==generation else{throw CancellationError()};return value}
    func preparationJobs()async throws->[TrackPreparationJob]{guard let api else{return []};let stamp=generation;let value=try await api.preparationJobs();guard stamp==generation else{throw CancellationError()};return value}
    static var demoCatalog:[MusicCatalogEntry]{DemoLibrary.songs.map{MusicCatalogEntry(id:$0.id,kind:.song,title:$0.title,artist:$0.artist ?? "Cadence Sessions",album:$0.album)}+[
        MusicCatalogEntry(id:"demo-outside",kind:.song,title:"Beyond the Library",artist:"Catalog Demo",album:"Not saved locally"),
        MusicCatalogEntry(id:"demo-artist",kind:.artist,title:"Cadence Sessions",artist:"Cadence Sessions"),
        MusicCatalogEntry(id:"demo-album",kind:.album,title:"Easy Miles",artist:"Cadence Sessions")
    ]}
    func signOut(){if let file{try? FileManager.default.removeItem(at:file)};let old=api;configure(nil);Task{await old?.signOut()}}
    static var demoTracks:[DiscoverTrack]{DemoLibrary.songs.map{DiscoverTrack(id:$0.id,title:$0.title,artistName:$0.artist,album:$0.album,previewURL:nil,durationMS:($0.duration ?? 0)*1000)}}
    private static func demo()->DiscoverSnapshot{
        let artist=DiscoverArtist(mbid:"11111111-1111-1111-1111-111111111111",name:"Cadence Sessions",tags:["Instrumental"],sourceArtists:["Your favorites"])
        let f=DateFormatter();f.dateFormat="yyyy-MM-dd";f.timeZone=TimeZone(secondsFromGMT:0);f.locale=Locale(identifier:"en_US_POSIX")
        let recent=DiscoverRelease(id:"22222222-2222-2222-2222-222222222222",albumName:"Fresh Light",artistName:"Cadence Sessions",artistMbid:artist.mbid,releaseDate:f.string(from:Date().addingTimeInterval(-86400)),albumType:"Single")
        let next=DiscoverRelease(id:"33333333-3333-3333-3333-333333333333",albumName:"On the Horizon",artistName:"Cadence Sessions",artistMbid:artist.mbid,releaseDate:f.string(from:Date().addingTimeInterval(14*86400)),albumType:"Album")
        return DiscoverSnapshot(response:DiscoverResponse(recommendations:[artist],globalTop:[artist],configured:true,provider:"Demo"),releases:[recent,next],playlists:[DiscoverPlaylist(id:"1",name:"A little fresh air",trackCount:3,curator:"Cadence Sessions")])
    }
}
#endif
