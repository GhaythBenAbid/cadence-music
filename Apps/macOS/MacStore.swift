import Foundation
import SwiftUI
import AppKit
import Combine
import CadenceCore

@MainActor final class MacStore:ObservableObject {
    struct Catalog:Codable {var albums:[Album];var playlists:[Playlist];var favorites:[Song]}
    @Published var credentials=KeychainStore.load()
    @Published var hasMoreAlbums=false
    @Published var albums:[Album]=[]
    @Published var playlists:[Playlist]=[]
    @Published var favorites:[Song]=[]
    @Published var artwork:[String:Data]=[:]
    @Published var discovery:[Song]=[]
    @Published var playlistRole:Bool?
    @Published var demo=false
    @Published var busy=false
    @Published var error:String?
    @Published var offlineIDs:Set<String>=[]
    @Published var downloading:Set<String>=[]
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
    private var deviceObserver:AnyCancellable?
    let audio=AudioController()
    let remote=PrivateMacServer()
    private var accountGeneration=UUID()
    private let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceMac",isDirectory:true)
    var api:SubsonicAPI?{credentials.map{SubsonicAPI(credentials:$0)}}
    var signedIn:Bool{credentials != nil || demo}
    var folder:URL{root.appendingPathComponent(credentials?.accountKey ?? "demo",isDirectory:true)}
    var offlineSongs:[Song]{Array(Set(albums.flatMap{$0.song ?? []}+playlists.flatMap{$0.entry ?? []}+favorites)).filter{offlineIDs.contains($0.id)}.sorted{$0.title.localizedStandardCompare($1.title) == .orderedAscending}}
    init(){
        remote.playback={ [weak self] in self?.playbackState() ?? PhonePlayback(song:nil,isPlaying:false,elapsed:0,duration:0,shuffled:false,repeats:false,volume:1) }
        remote.command={ [weak self] command in
            guard let self else{throw CadenceError.message("Open Cadence on the Mac.")}
            guard !self.remote.playingOnPhone else{throw CadenceError.message("Playback is on iPhone. Choose the iPhone source on your Watch, or transfer playback back to this Mac.")};try self.audio.apply(command);return self.playbackState()
        }
        remote.transfer={ [weak self] operation in
            guard let self else{throw CadenceError.message("Open Cadence on your Mac.")}
            switch operation.direction{
            case .toMac:
                guard let snapshot=operation.snapshot else{throw CadenceError.message("The queue is missing.")};self.discover.preview.stop();try self.audio.install(snapshot,autoplay:operation.play);return TransferredPlayback(snapshot:self.audio.playbackSnapshot(),play:self.audio.isPlaying)
            case .toPhone:
                let offer=self.remote.pendingInstruction
                let result=TransferredPlayback(snapshot:offer?.kind == .continueOnPhone ? (offer?.snapshot ?? self.audio.playbackSnapshot()) : self.audio.playbackSnapshot(),play:offer?.kind == .continueOnPhone && offer?.snapshot != nil ? (offer?.play ?? false) : self.audio.isPlaying)
                try result.snapshot.validate();guard !result.snapshot.queue.entries.isEmpty else{throw CadenceError.message("There is no queue on the Mac to transfer.")};self.audio.pause();return result
            case .editQueue:
                guard let snapshot=operation.snapshot,let expected=operation.expectedQueue else{throw CadenceError.message("The queue edit is incomplete.")};try self.audio.replaceQueue(snapshot,expected:expected);return TransferredPlayback(snapshot:self.audio.playbackSnapshot(),play:self.audio.isPlaying)
            case .inspect:return TransferredPlayback(snapshot:self.audio.playbackSnapshot(),play:self.audio.isPlaying)
            }
        }
        audio.systemRoute={ [weak self] command in
            guard let self,self.remote.playingOnPhone else{return false}
            if let command{self.deviceCommand(command)}else{self.togglePlayback()};return true
        }
        deviceObserver=remote.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        loadCatalog()
        remote.configure(credentials);prepareAudio()
        audio.onListeningEvent={ [weak self] account,event in self?.history.record(event,account:account) }
        historyObserver=history.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        globalObserver=globalPlayback.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        discoveryObserver=discover.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        previewObserver=audio.$isPlaying.sink{[weak self] playing in self?.objectWillChange.send();if playing{self?.discover.preview.stop()}}
        if ProcessInfo.processInfo.arguments.contains("--demo"){enterDemo()}
    }
    func playbackState()->PhonePlayback{
        var thumbnail:Data?
        if let song=audio.current,let data=song.coverArt.flatMap({artwork[$0]}),let image=NSImage(data:data){
            if let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),let context=CGContext(data:nil,width:96,height:96,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue){
                context.draw(cg,in:CGRect(x:0,y:0,width:96,height:96))
                if let rendered=context.makeImage(){thumbnail=NSBitmapImageRep(cgImage:rendered).representation(using:.jpeg,properties:[.compressionFactor:0.4])}
            }
            if (thumbnail?.count ?? 0)>12000{thumbnail=nil}
        }
        return PhonePlayback(song:audio.current,isPlaying:audio.isPlaying,elapsed:audio.elapsed,duration:audio.duration,shuffled:audio.isShuffled,repeats:audio.repeats,volume:Double(audio.volume),artwork:thumbnail)
    }
    func login(server:String,user:String,password:String) async {
        busy=true;defer{busy=false}
        do{
            let c=ServerCredentials(server:try ServerCredentials.normalizedServer(server),username:user,password:password)
            guard !c.username.isEmpty,!password.isEmpty else{throw CadenceError.message("Enter your username and password.")}
            try await SubsonicAPI(credentials:c).ping();remote.configure(nil);accountGeneration=UUID();audio.stop();try KeychainStore.save(c);credentials=c;remote.configure(c);demo=false;albums=[];playlists=[];favorites=[];artwork=[:];loadCatalog();prepareAudio();await refresh()
        }catch{self.error=message(error)}
    }
    func enterDemo(){hasMoreAlbums=false;remote.configure(nil);accountGeneration=UUID();audio.persist();demo=true;credentials=nil;albums=DemoLibrary.albums;playlists=DemoLibrary.playlists;favorites=DemoLibrary.songs;discovery=DemoLibrary.songs;playlistRole=true;artwork=[:];offlineIDs=[];prepareAudio();error=nil}
    func refresh() async {
        guard let api,!demo else{return};let generation=accountGeneration
        Task{await discover.refresh()}
        busy=true;defer{busy=false}
        do{
            async let a=api.albums();async let p=api.playlists();async let f=api.favorites()
            let result=try await(a,p,f);guard generation==accountGeneration else{return}
            // Retain cached track lists so previously opened albums remain usable offline.
            hasMoreAlbums=result.0.count==100;albums=result.0.map{new in var value=new;value.song=albums.first{$0.id==new.id}?.song;return value}
            playlists=result.1.map{new in var value=new;value.entry=playlists.first{$0.id==new.id}?.entry;return value}
            favorites=result.2;error=nil;let found=try? await api.randomSongs();let permission=try? await api.playlistPermission();guard generation==accountGeneration else{return};discovery=found ?? discovery;playlistRole=permission;saveCatalog();scanOffline()
        }catch{if generation==accountGeneration{self.error=message(error)}}
    }
    func loadMoreAlbums()async {
        guard !busy,!demo,hasMoreAlbums,let api else{return}
        let account=credentials?.accountKey;busy=true;defer{busy=false}
        do{let page=try await api.albums(offset:albums.count);guard account==credentials?.accountKey,!demo else{return};var seen=Set(albums.map(\.id));albums+=page.filter{seen.insert($0.id).inserted};hasMoreAlbums=page.count==100;saveCatalog()}
        catch{if account==credentials?.accountKey{self.error="More albums couldn't load. Check your server connection and try again."}}
    }
    func songs(_ album:Album) async throws->[Song]{
        if demo{return DemoLibrary.songs};let generation=accountGeneration
        do{guard let api else{return []};let full=try await api.album(album.id);guard generation==accountGeneration else{throw CancellationError()};if let i=albums.firstIndex(where:{$0.id==album.id}){albums[i]=full};saveCatalog();scanOffline();return full.song ?? []}
        catch{if let cached=album.song{return cached};throw error}
    }
    func songs(_ playlist:Playlist) async throws->[Song]{
        if demo{return playlist.entry ?? []};let generation=accountGeneration
        do{guard let api else{return []};let full=try await api.playlist(playlist.id);guard generation==accountGeneration else{throw CancellationError()};if let i=playlists.firstIndex(where:{$0.id==playlist.id}){playlists[i]=full};saveCatalog();scanOffline();return full.entry ?? []}
        catch{if let cached=playlist.entry{return cached};throw error}
    }
    func useSavedMacQueue(){remote.useLocalPlayback();audio.resume()}
    func requestPhonePlayback(){do{try remote.instructPhone(PhoneInstruction(.continueOnPhone))}catch{self.error=error.localizedDescription}}
    func requestMacPlayback(){do{try remote.instructPhone(PhoneInstruction(.continueOnMac))}catch{self.error=error.localizedDescription}}
    func deviceCommand(_ command:PhoneCommand){
        if !applyingCatalog{catalogEpoch=UUID();globalPlayback.stopWaiting()}
        if remote.playingOnPhone{do{try remote.instructPhone(PhoneInstruction(.command,command:command))}catch{self.error=error.localizedDescription}}
        else{do{try audio.apply(command)}catch{self.error=error.localizedDescription}}
    }
    func togglePlayback(){deviceCommand(PhoneCommand(remote.playingOnPhone ? (remote.phonePlayback?.isPlaying==true ? .pause : .play) : (audio.isPlaying ? .pause : .play)))}
    func playImportedPlaylist(_ playlist:ImportedPlaylist)async throws->Bool {
        let stamp=accountGeneration
        guard !demo,let api else{return false}
        // Aurral getPlaylist returns only completed audio jobs, unlike its metadata count.
        let songs=try await api.playlist(playlist.subsonicID).entry ?? []
        guard accountGeneration==stamp else{throw CancellationError()}
        guard !songs.isEmpty else{return false};discover.preview.stop();play(songs);return true
    }
    func playDiscovery(_ track:DiscoverTrack,artist:String)async throws->Bool{
        let generation=accountGeneration,songs=try await search(track.title)
        guard generation==accountGeneration else{throw CancellationError()}
        guard let song=DiscoveryLinks.libraryMatch(track,artist:artist,songs:songs) else{return false}
        discover.preview.stop();play([song]);return true
    }
    func createCatalogPlaylist(_ name:String)async throws->Playlist{
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !title.isEmpty else{throw CadenceError.message("Give your playlist a name.")}
        let identity=credentials?.accountKey
        if demo{let playlist=Playlist(id:UUID().uuidString,name:title,entry:[]);playlists.append(playlist);return playlist}
        guard playlistRole != false,let api else{throw CadenceError.message("This account needs playlist/Flows permission.")}
        guard let playlist=try await api.createPlaylist(name:title,songs:[]) else{throw CadenceError.message("Aurral didn't confirm the new playlist. Check Listen before creating it again.")}
        guard identity==credentials?.accountKey else{throw CancellationError()};playlists.append(playlist);saveCatalog();return playlist
    }
    func configureCatalogPreparation(){
        let identity=credentials?.accountKey ?? (demo ? "cadence-demo" : nil)
        globalPlayback.configure(identity,lookup:{[weak self] entry in
            guard let self else{return nil};if self.demo{return DemoLibrary.songs.first{$0.id==entry.id}}
            return entry.libraryMatch(try await self.api?.search(entry.title,kind:.songs,size:100).song ?? [])
        },request:{[weak self] entry in guard let self else{throw CancellationError()};return try await self.discover.prepareTrack(entry)},jobs:{[weak self] in try await self?.discover.preparationJobs() ?? []})
        globalPlayback.hasPlaybackQueue={ [weak self] in self?.remote.playingOnPhone==true ? self?.remote.phonePlayback?.song != nil : self?.audio.current != nil }
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
                if remote.playingOnPhone{let snapshot=PlaybackSnapshot(queue:PlaybackQueue(songs:[song]),position:0,repeats:audio.repeats,volume:audio.volume,repeatMode:audio.repeatMode,autoplay:audio.autoplay);try await sendPreparedToPhone(PhoneInstruction(.continueOnPhone,snapshot:snapshot))}else{play([song])}
                catalogStarted.insert(item.groupID)
            }
        case .playNext:try await enqueuePrepared(song,next:true)
        case .enqueue:try await enqueuePrepared(song,next:false)
        case .favorite:
            guard !favorites.contains(where:{$0.id==song.id}) else{return}
            if !demo{try await api?.favorite(song,enabled:true)};guard identity==credentials?.accountKey else{throw CancellationError()};favorites.append(song);saveCatalog()
        case .playlist:
            guard let id=item.playlistID,let playlist=playlists.first(where:{$0.id==id}) else{throw CadenceError.message("The selected playlist was removed. Choose another playlist.")};try await add(song,to:playlist)
        case .download:await download([song]);guard offlineIDs.contains(song.id) else{throw CadenceError.message("Download is not saved. Retry from Downloads.")}
        }
    }
    private func enqueuePrepared(_ song:Song,next:Bool)async throws{
        if remote.playingOnPhone{try await sendPreparedToPhone(PhoneInstruction(.enqueue,song:song,playNext:next))}else{try audio.enqueueChecked(song,next:next)}
    }
    private func sendPreparedToPhone(_ instruction:PhoneInstruction)async throws{
        try remote.instructPhone(instruction)
        for _ in 0..<120{if remote.lastAcknowledgedInstructionID==instruction.id{return};try Task.checkCancellation();try await Task.sleep(for:.milliseconds(250))}
        throw CadenceError.message("The iPhone didn't confirm. Review playback before applying again.")
    }
    func searchCatalog(_ query:String,kind:SearchKind,offset:Int)async throws->SearchResults {
        let account=credentials?.accountKey,wasDemo=demo
        if !demo,let api {
            do{let value=try await api.search(query,kind:kind,offset:offset);guard account==credentials?.accountKey,!demo else{throw CancellationError()};return value}
            catch is CancellationError{throw CancellationError()}
            catch{guard account==credentials?.accountKey,!demo else{throw CancellationError()};let cached=(savedDownloads+favorites+albums.flatMap{$0.song ?? []}).filter{($0.title+" "+($0.artist ?? "")+" "+($0.album ?? "")).localizedCaseInsensitiveContains(query)};guard !cached.isEmpty else{throw error};return Self.localSearch(query:query,kind:kind,offset:offset,songs:cached,albums:albums)}
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
        if demo || artist.id.hasPrefix("local:"){return albums.filter{$0.artist==artist.name}}
        let account=credentials?.accountKey;let value=try await api?.artist(artist.id).album ?? [];guard account==credentials?.accountKey else{throw CancellationError()};return value
    }
    func search(_ query:String) async throws->[Song]{
        if demo{return DemoLibrary.songs.filter{($0.title+" "+$0.subtitle).localizedCaseInsensitiveContains(query)}}
        do{return try await api?.search(query).song ?? []}catch{let cached=Array(Set(savedDownloads+favorites+albums.flatMap{$0.song ?? []}+playlists.flatMap{$0.entry ?? []})).filter{($0.title+" "+$0.subtitle).localizedCaseInsensitiveContains(query)};if !cached.isEmpty{return cached};throw error}
    }
    private func playbackURL(_ song:Song)->URL?{
        if demo{return DemoLibrary.url(song)}
        let file=folder.appendingPathComponent(song.filename)
        return FileManager.default.fileExists(atPath:file.path) ? file : api?.authenticatedURL("stream",parameters:[.init(name:"id",value:song.id)])
    }
    func prepareAudio(){history.configure(credentials?.accountKey ?? (demo ? "cadence-demo" : nil));configureCatalogPreparation();discover.configure(credentials,demo:demo);audio.configureSession(account:credentials?.accountKey ?? (demo ? "cadence-demo" : nil),resolver:{[weak self] in self?.playbackURL($0)},artwork:{[weak self] song in song.coverArt.flatMap{self?.artwork[$0]}});audio.relatedSongs={[weak self] seed in
            guard let self else{return []};let account=self.credentials?.accountKey,wasDemo=self.demo
            if wasDemo{return DemoLibrary.songs}
            let result=try await self.api?.relatedSongs(to:seed) ?? [];guard self.credentials?.accountKey==account,!self.demo else{throw CancellationError()};return self.history.profile.recommendations(candidates:result,favorites:self.favorites,seed:seed)
        }}
    func play(_ songs:[Song],from song:Song?=nil,position:Double=0){
        if !applyingCatalog{catalogEpoch=UUID();globalPlayback.stopWaiting()}
        if remote.playingOnPhone{
            let snapshot=PlaybackSnapshot(queue:PlaybackQueue(songs:songs,startingAt:song),position:position,repeats:audio.repeats,volume:audio.volume,repeatMode:audio.repeatMode,autoplay:audio.autoplay)
            do{try remote.instructPhone(PhoneInstruction(.continueOnPhone,snapshot:snapshot,play:true))}catch{self.error=error.localizedDescription};return
        }
        audio.play(songs,startingAt:song,resolver:{[weak self] in self?.playbackURL($0)},artwork:{[weak self] song in song.coverArt.flatMap{self?.artwork[$0]}},position:position)}
    func enqueue(_ song:Song,next:Bool=false){
        if remote.playingOnPhone{do{try remote.instructPhone(PhoneInstruction(.enqueue,song:song,playNext:next))}catch{self.error=error.localizedDescription};return}
        prepareAudio();audio.enqueue(song,next:next)
    }
    func radio(_ seed:Song?=nil)async{
        let generation=accountGeneration
        let random=demo ? DemoLibrary.songs : ((try? await api?.randomSongs()) ?? discovery)
        let related=(!demo && seed != nil) ? ((try? await api?.relatedSongs(to:seed!)) ?? []) : []
        let mix=history.profile.recommendations(candidates:related+random,favorites:favorites,seed:seed);guard generation==accountGeneration else{return};if !mix.isEmpty{play(mix)}
    }
    func playlistForEditing(_ id:String)async throws->Playlist{if demo,let p=playlists.first(where:{$0.id==id}){return p};guard let api else{throw CadenceError.message("Sign in first.")};return try await api.playlist(id)}
    func savePlaylist(name:String,songs:[Song],original:Playlist?=nil)async throws{
        if demo{var value=original ?? Playlist(id:UUID().uuidString,name:name);value.name=name;value.entry=songs;value.songCount=songs.count;playlists.removeAll{$0.id==value.id};playlists.append(value);return}
        let generation=accountGeneration
        guard let api else{throw CadenceError.message("Sign in first.")};if playlistRole==nil{playlistRole=try? await api.playlistPermission()};guard playlistRole != false else{throw CadenceError.message("This Aurral account needs playlist/Flows permission.")}
        guard generation==accountGeneration else{throw CancellationError()};if let original{try await api.editPlaylist(original,name:name,songs:songs);let full=try await api.playlist(original.id);guard generation==accountGeneration else{return};if let i=playlists.firstIndex(where:{$0.id==full.id}){playlists[i]=full}}else{try await api.createPlaylist(name:name,songs:songs)};guard generation==accountGeneration else{return};await refresh()
    }
    func deletePlaylist(_ value:Playlist)async throws{if !demo{try await api?.deletePlaylist(value.id)};playlists.removeAll{$0.id==value.id};saveCatalog()}
    func add(_ song:Song,to playlist:Playlist)async throws{let stamp=accountGeneration;let full=try await playlistForEditing(playlist.id);guard stamp==accountGeneration else{throw CancellationError()};var songs=full.entry ?? [];guard !songs.contains(where:{$0.id==song.id}) else{return};songs.append(song);try await savePlaylist(name:full.name,songs:songs,original:full)}
    func favorite(_ song:Song) async {
        let enabled = !favorites.contains{$0.id==song.id};let generation=accountGeneration
        do{if !demo{try await api?.favorite(song,enabled:enabled)};guard generation==accountGeneration else{return};if enabled{favorites.append(song)}else{favorites.removeAll{$0.id==song.id}};saveCatalog()}catch{self.error=message(error)}
    }
    func download(_ songs:[Song]) async {
        guard let api,!demo else{return};let generation=accountGeneration,folder=self.folder
        for song in songs where !offlineIDs.contains(song.id) && !downloading.contains(song.id){
            downloading.insert(song.id)
            do{
                let source=try await api.download(song)
                guard generation==accountGeneration else{try? FileManager.default.removeItem(at:source);return}
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let target=folder.appendingPathComponent(song.filename)
                if FileManager.default.fileExists(atPath:target.path){try FileManager.default.removeItem(at:target)}
                try FileManager.default.moveItem(at:source,to:target);offlineIDs.insert(song.id)
                // Keep individual search downloads discoverable even when their album was never opened.
                var saved=loadDownloads();saved.removeAll{$0.id==song.id};saved.append(song);try JSONEncoder().encode(saved).write(to:folder.appendingPathComponent("downloads.json"),options:.atomic)
            }catch{if generation==accountGeneration{self.error=message(error)}}
            downloading.remove(song.id)
            if Task.isCancelled{break}
        }
    }
    func remove(_ song:Song){do{try FileManager.default.removeItem(at:folder.appendingPathComponent(song.filename));offlineIDs.remove(song.id)}catch{self.error=message(error)}}
    var savedDownloads:[Song]{loadDownloads().filter{offlineIDs.contains($0.id)}}
    func loadArt(_ id:String?) async {
        guard let id,artwork[id]==nil,let api else{return};let generation=accountGeneration
        let file=folder.appendingPathComponent("art-"+Song(id:id,title:"").filename+".jpg")
        if let data=try? Data(contentsOf:file){artwork[id]=data;return}
        if let data=try? await api.artwork(id),generation==accountGeneration{artwork[id]=data;try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try? data.write(to:file,options:.atomic)}
    }
    func makePlaylist(name:String,songs:[Song]) async {do{guard let api,!name.trimmingCharacters(in:.whitespaces).isEmpty else{return};try await api.createPlaylist(name:name,songs:songs);await refresh()}catch{self.error=message(error)}}
    func logout(){discover.signOut();remote.configure(nil);accountGeneration=UUID();audio.stop();KeychainStore.clear();credentials=nil;demo=false;prepareAudio();discovery=[];playlistRole=nil;albums=[];playlists=[];favorites=[];artwork=[:];offlineIDs=[];downloading=[];try? FileManager.default.removeItem(at:root)}
    private func loadDownloads()->[Song]{(try? Data(contentsOf:folder.appendingPathComponent("downloads.json"))).flatMap{try? JSONDecoder().decode([Song].self,from:$0)} ?? []}
    private func loadCatalog(){if let data=try? Data(contentsOf:folder.appendingPathComponent("catalog.json")),let c=try? JSONDecoder().decode(Catalog.self,from:data){albums=c.albums;playlists=c.playlists;favorites=c.favorites};scanOffline()}
    private func saveCatalog(){guard !demo else{return};try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try? JSONEncoder().encode(Catalog(albums:albums,playlists:playlists,favorites:favorites)).write(to:folder.appendingPathComponent("catalog.json"),options:.atomic)}
    private func scanOffline(){let all=albums.flatMap{$0.song ?? []}+playlists.flatMap{$0.entry ?? []}+favorites+loadDownloads();offlineIDs=Set(all.filter{FileManager.default.fileExists(atPath:folder.appendingPathComponent($0.filename).path)}.map(\.id))}
    private func message(_ error:Error)->String{(error as NSError).domain==NSURLErrorDomain ? "Can't reach your Aurral server. Check its address and your connection, or play saved downloads." : error.localizedDescription}
}
