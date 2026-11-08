import Foundation
import SwiftUI
import UIKit
import Combine
import CadenceCore

@MainActor final class PhoneStore: ObservableObject {
    static let shared=PhoneStore()
    @Published var credentials: ServerCredentials?
    @Published var hasMoreAlbums=false
    @Published var albums: [Album]=[]
    @Published var playlists: [Playlist]=[]
    @Published var favorites: [Song]=[]
    @Published var artwork: [String:Data]=[:]
    @Published var discovery:[Song]=[]
    @Published var playlistRole:Bool?
    @Published var offline=false
    private let catalog=CatalogCache()
    @Published var loading=false
    @Published var error: String?
    @Published var isDemo=false
    var preparing:Bool{preparation.active}
    var preparedCount:Int{preparation.preparedCount}
    var preparationMessage:String{preparation.message}
    lazy var preparation=WatchPreparation(local:local,transport:bridge,available:{[weak self] in self?.downloads.url($0)},requestDownloads:{[weak self] in self?.downloadManager.enqueue($0)},artwork:{[weak self] in self?.art($0)})
    private var preparationObserver:AnyCancellable?
    private var receiptObserver:AnyCancellable?
    let discover=DiscoveryModel()
    let globalPlayback=PreparationCenter()
    private var catalogEpoch=UUID()
    private var catalogGroups:[String:UUID]=[:]
    private var catalogStarted=Set<String>()
    private var catalogRevisions:[String:Int]=[:]
    private var applyingCatalog=false
    let history=ListeningHistory()
    private var historyObserver:AnyCancellable?
    private var globalObserver:AnyCancellable?
    private var discoveryObserver:AnyCancellable?
    private var previewObserver:AnyCancellable?
    let audio=AudioController()
    let local=LocalLibrary()
    let bridge=WatchBridge()
    let downloadManager=PhoneDownloadManager.shared
    var downloads:DeviceDownloads{downloadManager.downloads}
    @Published private(set) var downloading:Set<String>=[]
    private var downloadsObserver:AnyCancellable?
    let mac=PrivateMacClient()
    @Published var playingOnMac=false
    @Published var transferringPlayback=false
    @Published var deviceMessage:String?
    private var processedPhoneInstructions=Set<String>()
    private var lastInstruction:String?
    private var pendingPullID:String?
    private var pendingPush:(id:String,snapshot:PlaybackSnapshot,play:Bool)?
    var hasUnconfirmedIncomingTransfer:Bool{pendingPullID != nil}
    var hasUnconfirmedOutgoingTransfer:Bool{pendingPush != nil}
    private var handoffPollBusy=false
    private var handoffGeneration=UUID()
    let macDiscovery=MacDiscovery()
    private var pendingMac:MacEndpoint?
    private var macFetch:Task<MacRemoteStatus,Never>?
    private var macFetchID:UUID?
    private var remoteObserver:AnyCancellable?
    private var devicePlaybackObserver:AnyCancellable?
    private var requestedArtwork:Set<String>=[]
    var api:SubsonicAPI? { credentials.map{SubsonicAPI(credentials:$0)} }
    var signedIn:Bool { credentials != nil || isDemo }
    var username:String { isDemo ? "Demo listener" : credentials?.username ?? "" }
    var confirmedCount:Int {
        guard let mix=local.mix, let receipt=bridge.receipt(for:mix), receipt.mixID==mix.id, receipt.accountKey==mix.accountKey else { return 0 }
        return Set(receipt.readyIDs).intersection(Set(mix.songs.map(\.id))).count
    }
    init() {
        credentials=KeychainStore.load()
        macDiscovery.onFound={ [weak self] endpoint in
            guard let self else{return}
            if self.mac.endpoint==nil || self.mac.endpoint?.id==endpoint.id{try? self.mac.select(endpoint)}
        }
        bridge.macProvider={ [weak self] in await self?.fetchMacStatus() ?? MacRemoteStatus(message:"Open Cadence on iPhone.") }
        bridge.onMacCommand={ [weak self] command in
            guard let self else{throw CadenceError.message("Open Cadence on iPhone.")}
            _=try await self.mac.fetch(command);return self.mac.status
        }
        audio.systemRoute={ [weak self] command in
            guard let self,self.playingOnMac else{return false}
            let action=command ?? PhoneCommand(self.mac.status.playback?.isPlaying==true ? .pause : .play)
            Task{await self.commandMac(action)};return true
        }
        configureMac()
        devicePlaybackObserver=mac.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        downloadManager.configure(credentials)
        downloadsObserver=downloadManager.$jobs.sink{[weak self] jobs in self?.downloading=Set(jobs.filter{$0.state == .queued || $0.state == .running}.map{$0.song.id})}
        loadCatalog();prepareAudio()
        audio.onListeningEvent={ [weak self] account,event in self?.history.record(event,account:account) }
        historyObserver=history.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        globalObserver=globalPlayback.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        discoveryObserver=discover.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        previewObserver=audio.$isPlaying.sink{[weak self] playing in if playing{self?.discover.preview.stop()}}
        preparationObserver=preparation.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        receiptObserver=bridge.$receipt.sink{[weak self] in self?.preparation.receive($0)}
        downloadManager.onFilesReady={ [weak self] in await self?.preparation.flush() }
        preparation.configure(account:credentials?.accountKey)
        bridge.onFileTransferFinished={ [weak self] in self?.preparation.transferFinished($0,success:$1) }
        bridge.playbackProvider={ [weak self] in self?.playbackState() ?? PhonePlayback(song:nil,isPlaying:false,elapsed:0,duration:0,shuffled:false,repeats:false,volume:1) }
        bridge.onCommand={ [weak self] command in
            guard let self else{throw CadenceError.message("Open Cadence on your iPhone.")}
            guard !self.playingOnMac else{throw CadenceError.message("Playback is on Mac. Choose Mac on your Watch, or transfer playback to this iPhone.")};try self.audio.apply(command);return self.playbackState()
        }
        remoteObserver=audio.objectWillChange.debounce(for:.milliseconds(100),scheduler:RunLoop.main).sink{[weak self] in
            Task{@MainActor in guard let self else{return};self.bridge.sendPlayback(self.playbackState())}
        }
        bridge.onRequestMix={ [weak self] in if let mix=self?.local.mix { try? self?.bridge.sendMix(mix) };self?.preparation.retry() }
        bridge.onActivation={ [weak self] in if let mix=self?.local.mix { try? self?.bridge.sendMix(mix) };if let self{self.bridge.sendPlayback(self.playbackState());self.preparation.retry()} }
        if ProcessInfo.processInfo.arguments.contains("--demo") { enterDemo() }
    }
    private func configureMac(){
        handoffGeneration=UUID();playingOnMac=false;transferringPlayback=false;handoffPollBusy=false;processedPhoneInstructions=[];lastInstruction=nil;pendingPullID=nil;pendingPush=nil;deviceMessage=nil;macFetch?.cancel();macFetch=nil;macFetchID=nil;mac.configure(credentials);macDiscovery.configure(credentials)
        if credentials != nil,let pendingMac{try? mac.select(pendingMac);self.pendingMac=nil}
    }
    func connectMac(_ url:URL){
        do{let endpoint=try MacEndpoint.from(url);if playingOnMac,mac.endpoint != endpoint{throw CadenceError.message("Bring playback to this iPhone before connecting another Mac.")};if credentials==nil{pendingMac=endpoint;error="Sign in with the same Aurral account as your Mac to finish connecting."}else{try mac.select(endpoint);Task{_=await fetchMacStatus()}}}catch{self.error=error.localizedDescription}
    }
    func pollPlaybackDevice()async{
        guard !handoffPollBusy,!transferringPlayback,credentials != nil,mac.endpoint != nil else{return}
        let generation=handoffGeneration;handoffPollBusy=true;defer{if generation==handoffGeneration{handoffPollBusy=false}}
        let account=credentials?.accountKey
        do{
            let response=try await mac.poll(phonePlayback:playbackState(),acknowledged:lastInstruction)
            guard account==credentials?.accountKey else{return}
            guard let instruction=response.instruction,!processedPhoneInstructions.contains(instruction.id) else{return}
            try instruction.validate()
            switch instruction.kind{
            case .continueOnPhone:try await continueOnPhone(id:instruction.id)
            case .continueOnMac:try await continueOnMac(id:instruction.id)
            case .command:guard !playingOnMac else{throw CadenceError.message("Playback moved to Mac before the phone command arrived.")};if let command=instruction.command{try audio.apply(command)}
            case .enqueue:guard !playingOnMac else{throw CadenceError.message("Playback moved to Mac before the queue edit arrived.")};if let song=instruction.song{try audio.enqueueChecked(song,next:instruction.playNext ?? false)}
            }
            guard generation==handoffGeneration,account==credentials?.accountKey else{return}
            processedPhoneInstructions.insert(instruction.id);lastInstruction=instruction.id
            if processedPhoneInstructions.count>100{processedPhoneInstructions=[instruction.id]}
        }catch is CancellationError{}catch{deviceMessage="Device unavailable: "+error.localizedDescription}
    }
    func continueOnMac(snapshot:PlaybackSnapshot?=nil,play:Bool?=nil,id:String=UUID().uuidString)async throws{
        guard !transferringPlayback else{throw CadenceError.message("A playback transfer is already in progress.")}
        let generation=handoffGeneration;transferringPlayback=true;defer{if generation==handoffGeneration{transferringPlayback=false}};let account=credentials?.accountKey
        _=try await mac.fetch();guard account==credentials?.accountKey else{throw CancellationError()};guard mac.lastResponse?.capabilities?.contains("handoff-v1")==true else{throw CadenceError.message("Update Cadence on your Mac to use handoff.")}
        let value=snapshot ?? audio.playbackSnapshot(),wasPlaying=play ?? audio.isPlaying
        try value.validate();guard !value.queue.entries.isEmpty else{throw CadenceError.message("Choose music before transferring it.")}
        audio.pause();pendingPush=(id,value,wasPlaying);playingOnMac=true;deviceMessage="Transferring your queue to Mac…"
        do{
            _=try await mac.transfer(PlaybackTransfer(.toMac,snapshot:value,play:wasPlaying),id:id)
            guard account==credentials?.accountKey else{throw CancellationError()};pendingPush=nil;deviceMessage="Playing on "+(mac.endpoint?.name ?? "Mac")
        }catch{if account==credentials?.accountKey{deviceMessage="Transfer not confirmed. This iPhone stays paused; check the Mac before trying again."};throw error}
    }
    func useSavedPhoneQueue(){playingOnMac=false;pendingPush=nil;pendingPullID=nil;deviceMessage="Using this iPhone. The unreachable Mac could not be stopped.";audio.resume()}
    func retryOutgoingTransfer()async throws{guard let pendingPush else{return};try await continueOnMac(snapshot:pendingPush.snapshot,play:pendingPush.play,id:pendingPush.id)}
    func continueOnPhone(id:String?=nil)async throws{
        guard !transferringPlayback else{throw CadenceError.message("A playback transfer is already in progress.")}
        let generation=handoffGeneration;transferringPlayback=true;defer{if generation==handoffGeneration{transferringPlayback=false}};let account=credentials?.accountKey
        let requestID=id ?? pendingPullID ?? UUID().uuidString;pendingPullID=requestID;deviceMessage="Bringing the Mac queue to this iPhone…"
        let result=try await mac.transfer(PlaybackTransfer(.toPhone),id:requestID)
        guard account==credentials?.accountKey else{throw CancellationError()}
        discover.preview.stop();try audio.install(result.snapshot,autoplay:result.play);playingOnMac=false;pendingPullID=nil;deviceMessage="Playback is on this iPhone."
    }
    func commandMac(_ command:PhoneCommand)async{
        if globalPlayback.waiting{globalPlayback.stopWaiting()}
        do{_=try await mac.fetch(command)}catch{deviceMessage=error.localizedDescription}
    }
    func fetchMacStatus()async->MacRemoteStatus{
        if let task=macFetch{return await task.value}
        guard credentials != nil else{return MacRemoteStatus(message:"Sign in to Aurral on this iPhone first.")}
        guard mac.endpoint != nil else{return MacRemoteStatus(message:"Connect a Mac in Cadence on iPhone under You → Mac playback.")}
        let id=UUID();let task=Task{[mac] in _=try? await mac.fetch();return mac.status};macFetch=task;macFetchID=id
        let result=await task.value;if macFetchID==id{macFetch=nil;macFetchID=nil};return result
    }
    func playbackState()->PhonePlayback{
        var thumbnail:Data?
        if let song=audio.current,let source=art(song),let image=UIImage(data:source){
            let renderer=UIGraphicsImageRenderer(size:CGSize(width:96,height:96));thumbnail=renderer.image{_ in image.draw(in:CGRect(x:0,y:0,width:96,height:96))}.jpegData(compressionQuality:0.4)
            if (thumbnail?.count ?? 0)>12000{thumbnail=nil}
        }
        return PhonePlayback(song:audio.current,isPlaying:audio.isPlaying,elapsed:audio.elapsed,duration:audio.duration,shuffled:audio.isShuffled,repeats:audio.repeats,volume:Double(audio.volume),artwork:thumbnail)
    }
    func login(server:String,username:String,password:String) async {
        loading=true;error=nil;defer{loading=false}
        do {
            let credentials=ServerCredentials(server:try ServerCredentials.normalizedServer(server),username:username,password:password)
            guard !credentials.username.isEmpty,!password.isEmpty else { throw CadenceError.message("Enter your username and password.") }
            try await SubsonicAPI(credentials:credentials).ping()
            if self.credentials?.accountKey != credentials.accountKey { local.clear();bridge.clearRemote() }
            try KeychainStore.save(credentials);self.credentials=credentials;configureMac();downloadManager.configure(credentials);preparation.configure(account:credentials.accountKey);isDemo=false;loadCatalog();prepareAudio()
            await refresh()
        } catch { self.error=friendly(error) }
    }
    func enterDemo() {
        hasMoreAlbums=false
        audio.persist()
        isDemo=true;credentials=nil;configureMac();downloadManager.configure(nil,demo:true);preparation.configure(account:"cadence-demo");albums=DemoLibrary.albums;playlists=DemoLibrary.playlists;favorites=DemoLibrary.songs;discovery=DemoLibrary.songs;playlistRole=true;offline=false;prepareAudio();error=nil
    }
    func refresh() async {
        guard let api, !isDemo else { return }
        Task{await discover.refresh()}
        let account=credentials?.accountKey
        loading=true;defer{loading=false}
        do {
            async let a=api.albums();async let p=api.playlists();async let f=api.favorites()
            let result=try await(a,p,f);guard account==credentials?.accountKey,!isDemo else{return}
            hasMoreAlbums=result.0.count==100;albums=result.0.map{album in var next=album;next.song=albums.first{$0.id==album.id}?.song;return next}
            playlists=result.1.map{value in var next=value;next.entry=playlists.first{$0.id==value.id}?.entry;return next};favorites=result.2;error=nil;offline=false
            let found=try? await api.randomSongs();let permission=try? await api.playlistPermission();guard account==credentials?.accountKey,!isDemo else{return};discovery=found ?? discovery;playlistRole=permission;saveCatalog()
        } catch {guard account==credentials?.accountKey,!isDemo else{return};offline=true;if downloads.songs.isEmpty && albums.isEmpty{self.error=friendly(error)}}
    }
    func loadMoreAlbums()async {
        guard !loading,!isDemo,hasMoreAlbums,let api else{return}
        let account=credentials?.accountKey;loading=true;defer{loading=false}
        do{let page=try await api.albums(offset:albums.count);guard account==credentials?.accountKey,!isDemo else{return};var seen=Set(albums.map(\.id));albums+=page.filter{seen.insert($0.id).inserted};hasMoreAlbums=page.count==100;saveCatalog()}
        catch{if account==credentials?.accountKey{self.error="More albums couldn't load. Check your server connection and try again."}}
    }
    func songs(for album:Album)async throws->[Song]{
        if isDemo{return DemoLibrary.songs}
        let account=credentials?.accountKey
        if offline,let saved=albums.first(where:{$0.id==album.id})?.song{return saved}
        do{guard let api else{return []};let full=try await api.album(album.id);guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};if let i=albums.firstIndex(where:{$0.id==album.id}){albums[i]=full};saveCatalog();return full.song ?? []}
        catch{guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};if let saved=albums.first(where:{$0.id==album.id})?.song{return saved};throw error}
    }
    func songs(for playlist:Playlist)async throws->[Song]{try await playlistForEditing(playlist.id).entry ?? []}
    func playlistForEditing(_ id:String)async throws->Playlist{
        if isDemo,let playlist=playlists.first(where:{$0.id==id}){return playlist}
        let account=credentials?.accountKey
        do{guard let api else{throw CadenceError.message("Sign in first.")};let full=try await api.playlist(id);guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};if let i=playlists.firstIndex(where:{$0.id==id}){playlists[i]=full};saveCatalog();return full}
        catch{guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};if let saved=playlists.first(where:{$0.id==id}),saved.entry != nil{return saved};throw error}
    }
    private func loadCatalog(){albums=[];playlists=[];favorites=[];discovery=[];playlistRole=nil;guard let account=credentials?.accountKey,let saved=catalog.load(account:account) else{return};albums=saved.albums;playlists=saved.playlists;favorites=saved.favorites;discovery=saved.discovery;playlistRole=saved.playlistRole}
    private func saveCatalog(){guard let account=credentials?.accountKey else{return};catalog.save(CatalogSnapshot(albums:albums,playlists:playlists,favorites:favorites,discovery:discovery,playlistRole:playlistRole),account:account)}
    private func playbackURL(_ song:Song)->URL?{
        if let cached=downloads.url(song){return cached};if isDemo{return DemoLibrary.url(song)}
        if local.mix?.accountKey==credentials?.accountKey,let file=local.localURL(song){return file}
        return api?.authenticatedURL("stream",parameters:[.init(name:"id",value:song.id)])
    }
    func prepareAudio(){history.configure(credentials?.accountKey ?? (isDemo ? "cadence-demo" : nil));configureCatalogPreparation();discover.configure(credentials,demo:isDemo);audio.configureSession(account:credentials?.accountKey ?? (isDemo ? "cadence-demo" : nil),resolver:{[weak self] in self?.playbackURL($0)},artwork:{[weak self] in self?.art($0)});audio.relatedSongs={[weak self] seed in
            guard let self else{return []};let account=self.credentials?.accountKey,wasDemo=self.isDemo
            if wasDemo{return DemoLibrary.songs}
            let result=try await self.api?.relatedSongs(to:seed) ?? [];guard self.credentials?.accountKey==account,!self.isDemo else{throw CancellationError()};return self.history.profile.recommendations(candidates:result,favorites:self.favorites,seed:seed)
        }}
    func enqueue(_ song:Song,next:Bool=false){
        if playingOnMac{
            guard !transferringPlayback,!hasUnconfirmedOutgoingTransfer else{error="Confirm the playback transfer before editing its queue.";return}
            Task{do{var remote=try await mac.transfer(PlaybackTransfer(.inspect));let baseline=remote.snapshot.queue.entries.map(\.id);remote.snapshot.queue.append(song,next:next);_=try await mac.transfer(PlaybackTransfer(.editQueue,snapshot:remote.snapshot,expectedQueue:baseline))}catch{self.error=error.localizedDescription}};return
        }
        prepareAudio();audio.enqueue(song,next:next)
    }
    func radio(_ seed:Song?=nil)async{
        let account=credentials?.accountKey,demo=isDemo
        let random=isDemo ? DemoLibrary.songs : ((try? await api?.randomSongs()) ?? discovery)
        let related: [Song]
        if let seed,!isDemo{related=(try? await api?.relatedSongs(to:seed)) ?? []}else{related=[]}
        let mix=history.profile.recommendations(candidates:related+random,favorites:favorites,seed:seed)
        guard account==credentials?.accountKey,demo==isDemo else{return};if !mix.isEmpty{play(mix)}
    }
    func playImportedPlaylist(_ playlist:ImportedPlaylist)async throws->Bool {
        let account=credentials?.accountKey
        guard !isDemo,let api else{return false}
        // Aurral getPlaylist returns only completed audio jobs, unlike its metadata count.
        let songs=try await api.playlist(playlist.subsonicID).entry ?? []
        guard account==credentials?.accountKey,!isDemo else{throw CancellationError()}
        guard !songs.isEmpty else{return false};discover.preview.stop();play(songs);return true
    }
    func playDiscovery(_ track:DiscoverTrack,artist:String)async throws->Bool{
        let account=credentials?.accountKey,demo=isDemo
        let songs=try await search(track.title).song ?? []
        guard account==credentials?.accountKey,demo==isDemo else{throw CancellationError()}
        guard let song=DiscoveryLinks.libraryMatch(track,artist:artist,songs:songs) else{return false}
        discover.preview.stop();play([song]);return true
    }
    func createCatalogPlaylist(_ name:String)async throws->Playlist{
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !title.isEmpty else{throw CadenceError.message("Give your playlist a name.")}
        let identity=credentials?.accountKey
        if isDemo{let playlist=Playlist(id:UUID().uuidString,name:title,entry:[]);playlists.append(playlist);return playlist}
        guard playlistRole != false,let api else{throw CadenceError.message("This account needs playlist/Flows permission.")}
        guard let playlist=try await api.createPlaylist(name:title,songs:[]) else{throw CadenceError.message("Aurral didn't confirm the new playlist. Check Listen before creating it again.")}
        guard identity==credentials?.accountKey else{throw CancellationError()};playlists.append(playlist);saveCatalog();return playlist
    }
    func configureCatalogPreparation(){
        let identity=credentials?.accountKey ?? (isDemo ? "cadence-demo" : nil)
        globalPlayback.configure(identity,lookup:{[weak self] entry in
            guard let self else{return nil};if self.isDemo{return DemoLibrary.songs.first{$0.id==entry.id}}
            return entry.libraryMatch(try await self.api?.search(entry.title,kind:.songs,size:100).song ?? [])
        },request:{[weak self] entry in guard let self else{throw CancellationError()};return try await self.discover.prepareTrack(entry)},jobs:{[weak self] in try await self?.discover.preparationJobs() ?? []})
        globalPlayback.hasPlaybackQueue={ [weak self] in self?.playingOnMac==true ? self?.mac.status.playback?.song != nil : self?.audio.current != nil }
        globalPlayback.serverURL=credentials?.server
        globalPlayback.apply={ [weak self] item in guard let self else{throw CancellationError()};try await self.applyPrepared(item) }
    }
    func playGlobal(_ entry:MusicCatalogEntry){catalogAction([entry],action:.play)}
    func catalogAction(_ entries:[MusicCatalogEntry],action:CatalogAction,playlistID:String?=nil){
        do{
            if action == .play{catalogEpoch=UUID();globalPlayback.stopWaiting();audio.pause()}
            if action == .favorite{for entry in entries{history.bookmark(entry)}}
            let group=try globalPlayback.submit(entries,action:action,playlistID:playlistID);catalogGroups[group]=catalogEpoch;catalogRevisions[group]=audio.playbackRevision
            Task{await globalPlayback.sync()}
        }catch{self.error=error.localizedDescription}
    }
    func resumePrepared(_ group:String){catalogGroups[group]=catalogEpoch;catalogRevisions[group]=audio.playbackRevision;catalogStarted.remove(group);globalPlayback.allow(group);Task{await globalPlayback.sync()}}
    private func applyPrepared(_ item:CatalogPreparation)async throws{
        let identity=credentials?.accountKey
        guard let song=item.song else{throw CadenceError.message("Audio is not ready yet.")}
        if [.play,.playNext,.enqueue].contains(item.action){guard catalogGroups[item.groupID]==catalogEpoch else{throw CadenceError.message("Playback changed. Apply the prepared music when ready.")}}
        switch item.action{
        case .play:
            if catalogStarted.contains(item.groupID){try await enqueuePrepared(song,next:false)}else{
                guard catalogRevisions[item.groupID]==audio.playbackRevision else{throw CadenceError.message("Playback changed. Apply this album when ready.")}
                applyingCatalog=true;defer{applyingCatalog=false}
                if playingOnMac{let snapshot=PlaybackSnapshot(queue:PlaybackQueue(songs:[song]),position:0,repeats:audio.repeats,volume:audio.volume,repeatMode:audio.repeatMode,autoplay:audio.autoplay);try await continueOnMac(snapshot:snapshot,play:true)}else{play([song])}
                catalogStarted.insert(item.groupID)
            }
        case .playNext:try await enqueuePrepared(song,next:true)
        case .enqueue:try await enqueuePrepared(song,next:false)
        case .favorite:
            guard !favorites.contains(where:{$0.id==song.id}) else{return}
            if !isDemo{try await api?.favorite(song,enabled:true)};guard identity==credentials?.accountKey else{throw CancellationError()};favorites.append(song);saveCatalog()
        case .playlist:
            guard let id=item.playlistID,let playlist=playlists.first(where:{$0.id==id}) else{throw CadenceError.message("The selected playlist was removed. Choose another playlist.")};try await add(song,to:playlist)
        case .download:download([song])
        }
    }
    private func enqueuePrepared(_ song:Song,next:Bool)async throws{
        if playingOnMac{var result=try await mac.transfer(PlaybackTransfer(.inspect));guard result.snapshot.queue.entries.count<1000 else{throw CadenceError.message("The Mac queue is full. Remove upcoming songs first.")};let expected=result.snapshot.queue.entries.map(\.id);result.snapshot.queue.append(song,next:next);_=try await mac.transfer(PlaybackTransfer(.editQueue,snapshot:result.snapshot,expectedQueue:expected))}else{try audio.enqueueChecked(song,next:next)}
    }
    func searchCatalog(_ query:String,kind:SearchKind,offset:Int)async throws->SearchResults {
        let account=credentials?.accountKey,wasDemo=isDemo
        if !isDemo,let api {
            do{let value=try await api.search(query,kind:kind,offset:offset);guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};return value}
            catch is CancellationError{throw CancellationError()}
            catch{guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};let cached=(downloads.songs+favorites+albums.flatMap{$0.song ?? []}).filter{($0.title+" "+($0.artist ?? "")+" "+($0.album ?? "")).localizedCaseInsensitiveContains(query)};guard !cached.isEmpty else{throw error};return Self.localSearch(query:query,kind:kind,offset:offset,songs:cached,albums:albums)}
        }
        guard wasDemo else{return SearchResults()};return Self.localSearch(query:query,kind:kind,offset:offset,songs:DemoLibrary.songs,albums:DemoLibrary.albums)
    }
    private static func localSearch(query:String,kind:SearchKind,offset:Int,songs:[Song],albums:[Album])->SearchResults {
        switch kind{
        case .songs:return SearchResults(song:Array(songs.filter{($0.title+" "+($0.artist ?? "")).localizedCaseInsensitiveContains(query)}.dropFirst(offset).prefix(30)))
        case .albums:return SearchResults(album:Array(albums.filter{($0.name+" "+($0.artist ?? "")).localizedCaseInsensitiveContains(query)}.dropFirst(offset).prefix(30)))
        case .artists:let names=Set(songs.compactMap(\.artist)).sorted().filter{$0.localizedCaseInsensitiveContains(query)};return SearchResults(artist:Array(names.dropFirst(offset).prefix(30)).map{Artist(id:"local:"+$0,name:$0)})
        }
    }
    func artistAlbums(_ artist:Artist)async throws->[Album]{
        if isDemo || artist.id.hasPrefix("local:"){return albums.filter{$0.artist==artist.name}}
        let account=credentials?.accountKey;let value=try await api?.artist(artist.id).album ?? [];guard account==credentials?.accountKey else{throw CancellationError()};return value
    }
    func search(_ query:String) async throws -> SearchResults {
        if isDemo {return SearchResults(song:DemoLibrary.songs.filter{query.isEmpty || ($0.title+" "+$0.subtitle).localizedCaseInsensitiveContains(query)})}
        let cached=Array(Set(downloads.songs+favorites+albums.flatMap{$0.song ?? []}+playlists.flatMap{$0.entry ?? []})).filter{($0.title+" "+$0.subtitle).localizedCaseInsensitiveContains(query)}.sorted{$0.title<$1.title}
        if offline{return SearchResults(song:cached)}
        guard let api else{throw CadenceError.message("Sign in to search your library.")}
        do{return try await api.search(query)}catch{if !cached.isEmpty{return SearchResults(song:cached)};throw error}
    }
    func loadArt(_ id:String?) async {
        guard let id, artwork[id]==nil, !requestedArtwork.contains(id),let api else{return}
        let account=credentials?.accountKey
        requestedArtwork.insert(id)
        if let data=try? await api.artwork(id),account==credentials?.accountKey,!isDemo{artwork[id]=data}else{requestedArtwork.remove(id)}
    }
    func art(_ song:Song)->Data? { song.coverArt.flatMap{artwork[$0]} ?? local.artwork(song) }
    func play(_ songs:[Song],startingAt:Song?=nil,position:Double=0) {
        if !applyingCatalog{catalogEpoch=UUID();globalPlayback.stopWaiting()}
        if playingOnMac{
            let value=PlaybackSnapshot(queue:PlaybackQueue(songs:songs,startingAt:startingAt),position:position,repeats:audio.repeats,volume:audio.volume,repeatMode:audio.repeatMode,autoplay:audio.autoplay)
            Task{do{try await continueOnMac(snapshot:value,play:true)}catch{self.error=error.localizedDescription}};return
        }
        prepareAudio();audio.play(songs,startingAt:startingAt,resolver:{[weak self] in self?.playbackURL($0)},artwork:{[weak self] in self?.art($0)},position:position)
    }

    func download(_ songs:[Song]){guard signedIn else{return};downloadManager.enqueue(songs)}
    func cancelDownloads(){downloadManager.cancelAll()}
    func favorite(_ song:Song) async {
        let account=credentials?.accountKey
        let enabled = !favorites.contains(where:{$0.id==song.id})
        do {
            if !isDemo {try await api?.favorite(song,enabled:enabled)}
            guard account==credentials?.accountKey else{return};if enabled{favorites.append(song)}else{favorites.removeAll{$0.id==song.id}};saveCatalog()
        }catch{self.error=friendly(error)}
    }
    func savePlaylist(name:String,songs:[Song],original:Playlist?=nil)async throws{
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw CadenceError.message("Give your playlist a name.")}
        if isDemo{
            var playlist=original ?? Playlist(id:UUID().uuidString,name:name);playlist.name=name;playlist.entry=songs;playlist.songCount=songs.count
            playlists.removeAll{$0.id==playlist.id};playlists.append(playlist);return
        }
        guard let api else{throw CadenceError.message("Sign in first.")}
        let account=credentials?.accountKey
        if playlistRole==nil{let role=try? await api.playlistPermission();guard account==credentials?.accountKey,!isDemo else{throw CancellationError()};playlistRole=role}
        guard playlistRole != false else{throw CadenceError.message("This Aurral account needs playlist/Flows permission to create or edit playlists.")}
        if let original{try await api.editPlaylist(original,name:name,songs:songs)}else{try await api.createPlaylist(name:name,songs:songs)}
        guard account==credentials?.accountKey,!isDemo else{return};await refresh()
    }
    func deletePlaylist(_ playlist:Playlist)async throws{if !isDemo{guard let api else{return};try await api.deletePlaylist(playlist.id)};playlists.removeAll{$0.id==playlist.id};saveCatalog()}
    func add(_ song:Song,to playlist:Playlist)async throws{let account=credentials?.accountKey,demo=isDemo;let full=try await playlistForEditing(playlist.id);guard account==credentials?.accountKey,demo==isDemo else{throw CancellationError()};var songs=full.entry ?? [];guard !songs.contains(where:{$0.id==song.id}) else{return};songs.append(song);try await savePlaylist(name:full.name,songs:songs,original:full)}
    func makePlaylist(name:String,songs:[Song])async{do{try await savePlaylist(name:name,songs:songs)}catch{self.error=error.localizedDescription}}
    func prepareMix(name:String,songs:[Song],existing:RunMix?=nil){
        bridge.refresh()
        guard bridge.canTransfer else{error=bridge.status;return}
        guard let account=credentials?.accountKey ?? (isDemo ? "cadence-demo" : nil) else{return}
        do{try preparation.start(name:name,songs:songs,account:account,existing:existing);retryPreparation()}catch{self.error=friendly(error)}
    }
    func selectWatchMix(_ id:String){do{if preparation.active{cancelPreparation()};try local.select(id)}catch{self.error=error.localizedDescription}}
    func removeWatchMix(_ mix:RunMix){do{
        if bridge.supportsMultipleMixes{try bridge.removeRemoteMix(mix);if preparation.plan?.mix.id==mix.id{cancelPreparation()};_=try local.remove(WatchMixRemoval(mix))}
        else{cancelPreparation();local.clear();bridge.clearRemote()}
    }catch{self.error=error.localizedDescription}}
    func retryPreparation(){
        let ids=Set(preparation.plan?.mix.songs.map(\.id) ?? [])
        for job in downloadManager.jobs where ids.contains(job.song.id) && (job.state == .paused || job.state == .failed){downloadManager.retry(job.id)}
        preparation.retry()
    }
    func cancelPreparation(){preparation.cancel()}
    func logout(){discover.signOut();cancelPreparation();audio.stop();bridge.clearRemote();local.clear();if let account=credentials?.accountKey{catalog.clear(account:account)};KeychainStore.clear();credentials=nil;configureMac();cancelDownloads();downloads.eraseAll();downloadManager.configure(nil);isDemo=false;prepareAudio();albums=[];playlists=[];favorites=[];discovery=[];playlistRole=nil;artwork=[:];requestedArtwork=[];error=nil}
    private func friendly(_ error:Error)->String{ if (error as NSError).domain==NSURLErrorDomain{return "Can't reach your music server. Check your connection and server address, then try again."};return error.localizedDescription }
}
