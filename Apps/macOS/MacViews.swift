import SwiftUI
import AppKit
import CadenceCore

enum MacPalette {
    static let paper=Color(red:245/255,green:243/255,blue:235/255)
    static let ink=Color(red:22/255,green:33/255,blue:29/255)
    static let lime=Color(red:215/255,green:245/255,blue:103/255)
}
struct MacBrand:View {
    var body:some View{HStack(spacing:5){Image("CadenceMarkInk").resizable().scaledToFit().frame(width:42,height:42);Text("cadence").font(.system(size:29,weight:.semibold,design:.rounded)).tracking(-1)}.accessibilityElement(children:.ignore).accessibilityLabel("Cadence")}
}
struct MacCover:View {
    var title:String;var data:Data?;var size:CGFloat=60
    var body:some View{ZStack{if let data,let image=NSImage(data:data){Image(nsImage:image).resizable().scaledToFill()}else{LinearGradient(colors:[MacPalette.ink,Color(red:0.34,green:0.52,blue:0.4)],startPoint:.topLeading,endPoint:.bottomTrailing);Image("CadenceMarkLime").resizable().scaledToFit().padding(size*0.12)}}.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:max(8,size*0.08))).accessibilityHidden(true)}
}
struct MacRoot:View {
    @EnvironmentObject var store:MacStore
    @State private var page="library"
    @State private var selectedAlbum:Album?
    @State private var selectedPlaylist:Playlist?
    @State private var createPlaylist=false
    @State private var importSpotify=false
    var body:some View {
        Group{if store.signedIn{
            NavigationSplitView{
                VStack(alignment:.leading,spacing:20){MacBrand().padding(.horizontal,15).padding(.top,22)
                    List(selection:$page){Label("Listen",systemImage:"square.grid.2x2").tag("library");Label("Discover",systemImage:"sparkles").tag("discover");Label("Search",systemImage:"magnifyingglass").tag("search");Label("Your listening",systemImage:"clock.arrow.circlepath").tag("history");Label("Preparing music",systemImage:"clock.badge.arrow.circlepath").tag("preparing");Label("Favorites",systemImage:"heart").tag("favorites");Label("Downloads",systemImage:"arrow.down.circle").tag("downloads");Section("Your playlists"){ForEach(store.playlists){playlist in Label(playlist.name,systemImage:"music.note.list").tag("playlist:"+playlist.id)}};Section{Label("Your account",systemImage:"person.crop.circle").tag("account")}}
                    Button("New playlist",systemImage:"plus"){createPlaylist=true}.padding(.horizontal,20)
                    Button("Import Spotify playlist",systemImage:"square.and.arrow.down"){importSpotify=true}.padding(.horizontal,20)
                    Spacer(minLength:0)
                    Text("MUSIC FOR THE\nLONG WAY HOME.").font(.system(size:10,weight:.semibold)).tracking(1.8).foregroundStyle(.secondary).padding(24)
                }.background(MacPalette.paper).navigationSplitViewColumnWidth(min:215,ideal:235,max:280)
            }detail:{NavigationStack{
                Group{switch page{
                case "discover":DiscoverView(model:store.discover,pauseMain:{store.audio.pause()},playFromLibrary:{try await store.playDiscovery($0,artist:$1)})
                case "search":MacSearchView()
                case "history":ListeningHistoryView(history:store.history,model:store.discover,playback:store.globalPlayback,play:{store.play([$0],position:$1)},playGlobal:store.playGlobal,interaction:CatalogInteraction(history:store.history,playlists:store.playlists,act:{store.catalogAction($0,action:$1,playlistID:$2)},resume:store.resumePrepared,createPlaylist:store.createCatalogPlaylist))
                case "preparing":PreparationListView(center:store.globalPlayback,resume:store.resumePrepared)
                case "favorites":MacCollection(title:"Your favorites",songs:store.favorites)
                case "downloads":MacCollection(title:"Saved for later",songs:store.savedDownloads)
                case "account":MacAccountView().padding(40).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                default:if page.hasPrefix("playlist:"),let playlist=store.playlists.first(where:{"playlist:"+$0.id==page}){MacPlaylistView(playlist:playlist).id(playlist.id)}else{MacLibraryView()}
                }}.background(MacPalette.paper)
            }}.safeAreaInset(edge:.bottom,spacing:0){MacPlayer(audio:store.audio)}.task{await store.refresh()}
        }else{MacLoginView()}}
        .sheet(isPresented:$createPlaylist){MacPlaylistEditor()}
        .sheet(isPresented:$importSpotify,onDismiss:{Task{await store.refresh()}}){SpotifyImportView(model:store.discover,play:{try await store.playImportedPlaylist($0)},loadSongs:{try await store.songs(Playlist(id:$0.subsonicID,name:$0.name))},playSongs:{store.play($0)},refreshLibrary:{await store.refresh()}).id(store.discover.profileID)}
        .alert("A little pause",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("OK",role:.cancel){store.error=nil}}message:{Text(store.error ?? "")}
    }
}
struct MacLoginView:View {
    @EnvironmentObject var store:MacStore
    @State private var server=""
    @State private var user=""
    @State private var password=""
    var body:some View {
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:25){Image("CadenceMarkLime").resizable().scaledToFit().frame(width:100,height:100);Spacer();Text("A little music.\nA lot of miles.").font(.system(size:52,weight:.medium,design:.serif)).tracking(-1.8);Text("Your library, at home on your Mac.").font(.title3).foregroundStyle(.white.opacity(0.7));Spacer();Text("CADENCE / MUSIC FOR THE LONG WAY HOME").font(.system(size:10,weight:.semibold)).tracking(2)}.padding(55).frame(maxWidth:.infinity,alignment:.leading).background(MacPalette.ink).foregroundStyle(.white)
            VStack(alignment:.leading,spacing:21){MacBrand();Text("Make yourself at home.").font(.system(size:29,design:.serif));VStack(alignment:.leading,spacing:8){Text("Server URL").font(.subheadline.weight(.medium));TextField("https://music.example.com",text:$server).textFieldStyle(.roundedBorder).autocorrectionDisabled().accessibilityLabel("Server URL").accessibilityIdentifier("login.server")};TextField("Username",text:$user).textContentType(.username).textFieldStyle(.roundedBorder);SecureField("Password",text:$password).textContentType(.password).textFieldStyle(.roundedBorder)
                Button{Task{await store.login(server:server,user:user,password:password)}}label:{HStack{Text(store.busy ? "Connecting…" : "Let's listen");if store.busy{ProgressView().controlSize(.small)}}.frame(maxWidth:.infinity).padding(.vertical,7)}.buttonStyle(.borderedProminent).disabled(store.busy).keyboardShortcut(.defaultAction)
                Label("Use your Aurral server's HTTPS address. Connect its VPN if required.",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
                Button("Explore demo"){store.enterDemo()}.buttonStyle(.link).accessibilityIdentifier("mac.demo")
            }.padding(60).frame(width:470)
        }.background(MacPalette.paper)
    }
}
struct MacLibraryView:View {
    @EnvironmentObject var store:MacStore
    var body:some View {
        ScrollView{
            VStack(alignment:.leading,spacing:28){
                HStack(alignment:.top){VStack(alignment:.leading,spacing:8){Text("Find your rhythm.").font(.system(size:48,weight:.medium,design:.serif)).tracking(-1.8);Text("Good music. A little room to move.").foregroundStyle(.secondary)};Spacer();if store.busy{ProgressView().controlSize(.small)};Button{Task{await store.refresh()}}label:{Image(systemName:"arrow.clockwise")}.help("Refresh library")}
                HStack{VStack(alignment:.leading,spacing:10){Text("YOUR MUSIC. YOUR PACE.").font(.system(size:10,weight:.bold)).tracking(2);Text("Stay a little longer.").font(.system(size:32,weight:.medium,design:.serif));Text("Choose a record. Find a favorite. Let it play.").font(.subheadline)};Spacer();Image("CadenceMarkInk").resizable().scaledToFit().frame(width:108,height:108)}.padding(30).frame(maxWidth:.infinity).background(MacPalette.lime,in:RoundedRectangle(cornerRadius:24))
                VStack(alignment:.leading,spacing:12){Text("FROM YOUR LIBRARY").font(.caption.weight(.bold));Button("Play a library mix",systemImage:"sparkles"){Task{await store.radio()}};Text("A library mix influenced by favorites, followed artists and listening on this Mac.").font(.caption).foregroundStyle(.secondary);MacSongList(songs:Array(store.discovery.prefix(4)))}
                Text("ON REPEAT, ON PURPOSE").font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(.secondary)
                if store.albums.isEmpty{ContentUnavailableView("Your first soundtrack",systemImage:"music.note",description:Text("Add music in Aurral, then refresh your library."))}
                LazyVGrid(columns:[GridItem(.adaptive(minimum:165,maximum:215),spacing:25)],alignment:.leading,spacing:28){ForEach(store.albums){album in NavigationLink{MacAlbumView(album:album)}label:{VStack(alignment:.leading,spacing:8){MacCover(title:album.name,data:album.coverArt.flatMap{store.artwork[$0]},size:165);Text(album.name).font(.headline).lineLimit(1);Text(album.artist ?? "Your library").font(.caption).foregroundStyle(.secondary).lineLimit(1)}}.buttonStyle(.plain).accessibilityLabel("Open album \(album.name)").task{await store.loadArt(album.coverArt)}}}
                if store.hasMoreAlbums{Button("Load more albums"){Task{await store.loadMoreAlbums()}}.disabled(store.busy).accessibilityIdentifier("library.more")}
            }.padding(35)
        }.background(MacPalette.paper).foregroundStyle(MacPalette.ink).navigationTitle("Listen")
    }
}
struct MacAlbumView:View {
    @EnvironmentObject var store:MacStore
    let album:Album
    @State private var songs:[Song]=[]
    init(album:Album){self.album=album;_songs=State(initialValue:album.song ?? [])}
    var body:some View{MacCollection(title:album.name,songs:songs,cover:album.coverArt).task{do{songs=try await store.songs(album)}catch{store.error=error.localizedDescription}}}
}
struct MacPlaylistView:View {
    @EnvironmentObject var store:MacStore
    let playlist:Playlist
    @State private var songs:[Song]=[]
    init(playlist:Playlist){self.playlist=playlist;_songs=State(initialValue:playlist.entry ?? [])}
    var body:some View{MacCollection(title:playlist.name,songs:songs,cover:playlist.coverArt,playlist:playlist).task(id:playlist){do{songs=try await store.songs(playlist)}catch{store.error=error.localizedDescription}}}
}
struct MacCollection:View {
    @EnvironmentObject var store:MacStore
    var title:String;var songs:[Song];var cover:String?;var playlist:Playlist?=nil
    @State private var editPlaylist=false
    @State private var deletePlaylist=false
    @State private var playlistName=""
    @State private var newPlaylist=false
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:24){HStack(spacing:28){MacCover(title:title,data:cover.flatMap{store.artwork[$0]},size:150);VStack(alignment:.leading,spacing:14){Text(title).font(.system(size:37,weight:.medium,design:.serif));Text("\(songs.count) tracks").foregroundStyle(.secondary);HStack{Button{store.play(songs)}label:{Label("Play",systemImage:"play.fill")}.buttonStyle(.borderedProminent).disabled(songs.isEmpty);Button{Task{await store.download(songs)}}label:{Label("Save offline",systemImage:"arrow.down.circle")}.disabled(songs.isEmpty || store.demo);Button("Create playlist"){newPlaylist=true}.disabled(songs.isEmpty)}};Spacer()}
            MacSongList(songs:songs)
            if songs.isEmpty{ContentUnavailableView("Nothing here yet",systemImage:"music.note.list",description:Text("Choose music from your library to get started."))}
        }.padding(35)}.navigationTitle(title).task{await store.loadArt(cover)}
        .sheet(isPresented:$newPlaylist){MacPlaylistEditor(initialSongs:songs)}
        .toolbar{if let playlist,!playlist.id.hasPrefix("flow:"){Menu("Playlist"){Button("Edit playlist"){editPlaylist=true};Button("Delete playlist",role:.destructive){deletePlaylist=true}}}}
        .sheet(isPresented:$editPlaylist){MacPlaylistEditor(playlist:playlist)}
        .confirmationDialog("Delete this playlist?",isPresented:$deletePlaylist){Button("Delete playlist",role:.destructive){Task{do{if let playlist{try await store.deletePlaylist(playlist)}}catch{store.error=error.localizedDescription}}}}

    }
}
struct MacSongList:View {
    @EnvironmentObject var store:MacStore
    var songs:[Song]
    @State private var playlistSong:Song?
    var body:some View{LazyVStack(spacing:0){ForEach(Array(songs.enumerated()),id:\.element.id){index,song in
        HStack(spacing:13){Button{store.play(songs,from:song)}label:{HStack(spacing:13){Text("\(index+1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:25);MacCover(title:song.title,data:song.coverArt.flatMap{store.artwork[$0]},size:42);VStack(alignment:.leading,spacing:4){Text(song.title).font(.system(size:14,weight:.medium));Text(song.subtitle).font(.caption).foregroundStyle(.secondary)};Spacer()}.contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("Play \(song.title)")
            Menu{Button("Play next"){store.enqueue(song,next:true)};Button("Add to queue"){store.enqueue(song)};Button("Add to playlist"){playlistSong=song};Button("Play a library mix"){Task{await store.radio(song)}}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:24)
            Text(song.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if store.downloading.contains(song.id){ProgressView().controlSize(.small).frame(width:24)}else{Button{Task{if store.offlineIDs.contains(song.id){store.remove(song)}else{await store.download([song])}}}label:{Image(systemName:store.offlineIDs.contains(song.id) ? "checkmark.circle.fill" : "arrow.down.circle")}.buttonStyle(.plain).disabled(store.demo).help(store.offlineIDs.contains(song.id) ? "Remove download" : "Save offline")}
            Button{Task{await store.favorite(song)}}label:{Image(systemName:store.favorites.contains{$0.id==song.id} ? "heart.fill" : "heart")}.buttonStyle(.plain).help("Toggle favorite")
        }.padding(.vertical,11).padding(.horizontal,8).background(index.isMultiple(of:2) ? Color.white.opacity(0.65) : .clear,in:RoundedRectangle(cornerRadius:10)).task{await store.loadArt(song.coverArt)}
    }}.sheet(item:$playlistSong){song in PlaylistPicker(song:song,playlists:store.playlists,add:{try await store.add($0,to:$1)},create:{try await store.savePlaylist(name:$0,songs:$1,original:$2)})}}
}
struct MacSearchView:View {
    @EnvironmentObject var store:MacStore
    var body:some View{CatalogSearchView(interaction:CatalogInteraction(history:store.history,playlists:store.playlists,act:{store.catalogAction($0,action:$1,playlistID:$2)},resume:store.resumePrepared,createPlaylist:store.createCatalogPlaylist),model:store.discover,playback:store.globalPlayback,playGlobal:store.playGlobal,fetch:{try await store.searchCatalog($0,kind:$1,offset:$2)},artistAlbums:{try await store.artistAlbums($0)},songRow:{song,songs in AnyView(Button{store.play(songs,from:song)}label:{HStack{VStack(alignment:.leading){Text(song.title);Text(song.artist ?? "Unknown artist").font(.caption).foregroundStyle(.secondary)};Spacer();Text(song.durationLabel)}}.buttonStyle(.plain))},albumView:{AnyView(MacAlbumView(album:$0))})}
}

struct MacAccountView:View {
    @EnvironmentObject var store:MacStore
    @State private var logout=false
    var body:some View{VStack(alignment:.leading,spacing:22){MacBrand();Text(store.demo ? "Demo listener" : store.credentials?.username ?? "Your account").font(.title);Text("A little music. A lot of miles.").font(.system(.title2,design:.serif));Text("Cadence connects to your Aurral server over HTTPS; saved downloads play offline. Connect your VPN if your server requires it.").foregroundStyle(.secondary);if let server=store.credentials?.server{Link("Open your Aurral server",destination:server)};Divider();Text("Your Watch can control this Mac through Cadence on your iPhone. Keep Tailscale connected on both, and sign in with the same Aurral account. Offline Watch music is prepared on iPhone.").font(.callout).foregroundStyle(.secondary);MacRemoteCard(server:store.remote);Text("Credentials stay in Keychain. No analytics or advertising.").font(.caption).foregroundStyle(.secondary);Button(store.demo ? "Leave demo" : "Sign out and erase downloads",role:.destructive){logout=true}.confirmationDialog("Sign out?",isPresented:$logout){Button("Sign out",role:.destructive){store.logout()}}message:{Text("Saved music on this Mac will be removed.")};Spacer()}.frame(maxWidth:650,alignment:.leading)}
}
struct MacPlayer:View {
    @State private var showQueue=false
    @EnvironmentObject var store:MacStore
    @ObservedObject var audio:AudioController
    var body:some View{VStack(spacing:0){Divider();if store.remote.playingOnPhone{MacPhonePlayer()}else if let song=audio.current{
        HStack(spacing:20){Button{store.requestPhonePlayback()}label:{Image(systemName:"iphone.radiowaves.left.and.right")}.help("Continue on iPhone (keep its app open)").disabled(!store.remote.phoneAvailable);MacCover(title:song.title,data:song.coverArt.flatMap{store.artwork[$0]},size:55);VStack(alignment:.leading,spacing:5){Text(song.title).font(.headline).lineLimit(1);Text(song.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)}.frame(width:190,alignment:.leading)
            Button{audio.shuffle()}label:{Image(systemName:"shuffle").foregroundStyle(audio.isShuffled ? MacPalette.ink : .secondary)}.buttonStyle(.plain).help("Shuffle")
            Button{audio.previous()}label:{Image(systemName:"backward.end.fill")}.buttonStyle(.plain).help("Previous track")
            Button{audio.toggle()}label:{Image(systemName:audio.isPlaying ? "pause.fill" : "play.fill").frame(width:43,height:43).background(MacPalette.ink,in:Circle()).foregroundStyle(.white)}.buttonStyle(.plain).accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            Button{audio.next()}label:{Image(systemName:"forward.end.fill")}.buttonStyle(.plain).help("Next track")
            VStack(spacing:5){Slider(value:Binding(get:{min(audio.elapsed,max(1,audio.duration))},set:{audio.seek($0)}),in:0...max(1,audio.duration));HStack{Text(time(audio.elapsed));Spacer();Text(time(audio.duration))}.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)}.frame(minWidth:120)
            Button{audio.cycleRepeat()}label:{Image(systemName:audio.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(audio.repeats ? MacPalette.ink : .secondary)}.buttonStyle(.plain).help("Repeat")
            Button{showQueue=true}label:{Image(systemName:"list.bullet")}.buttonStyle(.plain).accessibilityLabel("Open queue")
            Image(systemName:"speaker.wave.2");Slider(value:$audio.volume,in:0...1).frame(width:85).accessibilityLabel("Volume")
        }.padding(.horizontal,25).padding(.vertical,17)
        if let error=audio.error{HStack{Text(error).font(.caption).foregroundStyle(.orange);Button("Retry"){audio.retryCurrent()};Button("Skip"){audio.next()}}.padding(.bottom,8)}
        }else{HStack{Image("CadenceMarkInk").resizable().scaledToFit().frame(width:29,height:29);Text("Find something worth a second listen.").font(.system(.body,design:.serif)).foregroundStyle(.secondary);Spacer()}.padding(20)}}.background(MacPalette.paper).foregroundStyle(MacPalette.ink).sheet(isPresented:$showQueue){QueueView(audio:audio)}.onChange(of:store.remote.playingOnPhone){_,value in if value{showQueue=false}}}
    private func time(_ value:Double)->String{let seconds=Int(value.isFinite ? max(0,value) : 0);return String(format:"%d:%02d",seconds/60,seconds%60)}
}

struct MacPlaylistEditor:View {
    @EnvironmentObject var store:MacStore
    var playlist:Playlist?
    var initialSongs:[Song]=[]
    var body:some View{PlaylistEditor(original:playlist,initialSongs:initialSongs,load:{try await store.playlistForEditing($0)},search:{try await store.search($0)},save:{try await store.savePlaylist(name:$0,songs:$1,original:$2)})}
}

struct MacPhonePlayer:View {
    @EnvironmentObject var store:MacStore
    @State private var localRecovery=false
    var body:some View{VStack(alignment:.leading,spacing:8){
        HStack(spacing:18){Image(systemName:"iphone");VStack(alignment:.leading){Text(store.remote.phonePlayback?.song?.title ?? "Playing on iPhone").font(.headline);Text("On iPhone · "+(store.remote.phonePlayback?.song?.artist ?? "")).font(.caption).foregroundStyle(.secondary)};Spacer();Group{Button("Previous"){store.deviceCommand(PhoneCommand(.previous))};Button(store.remote.phonePlayback?.isPlaying==true ? "Pause" : "Play"){store.togglePlayback()};Button("Next"){store.deviceCommand(PhoneCommand(.next))};Button("Continue on this Mac"){store.requestMacPlayback()}}.disabled(!store.remote.phoneAvailable)}
        if !store.remote.phoneAvailable{HStack{Text("iPhone unavailable. Open Cadence on it to transfer its latest queue.").font(.caption).foregroundStyle(.secondary);Button("Use saved Mac queue"){localRecovery=true}}}
    }.padding(20).confirmationDialog("Use the saved Mac queue?",isPresented:$localRecovery){Button("Use this Mac"){store.useSavedMacQueue()}}message:{Text("The unreachable iPhone cannot be stopped. Pause it first if it is still playing. This resumes the Mac’s saved queue, which may differ from the iPhone’s latest queue.")}}
}
