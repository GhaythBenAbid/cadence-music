import SwiftUI
import CadenceCore

extension Color { init(hex:UInt32){ self.init(.sRGB,red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,opacity:1) } }
enum Palette { static let paper=Color(hex:0xF5F3EB);static let ink=Color(hex:0x16211D);static let lime=Color(hex:0xD7F567);static let muted=Color(hex:0x748078);static let card=Color.white }

struct Cover:View {
    let title:String;var data:Data?;var size:CGFloat=64
    var body:some View {
        ZStack{
            if let data,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}
            else{
                LinearGradient(colors:[Palette.ink,Color(hex:0x457264),Color(hex:0xA8BE79)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Circle().stroke(.white.opacity(0.13),lineWidth:size*0.15).padding(size*0.17)
                Circle().fill(Palette.lime).frame(width:size*0.12,height:size*0.12)
                Text(String(title.prefix(1)).uppercased()).font(.system(size:size*0.27,weight:.medium,design:.serif)).foregroundStyle(.white).offset(x:-size*0.2,y:size*0.23)
            }
        }.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:max(10,size*0.09))).accessibilityHidden(true)
    }
}
struct Wordmark:View { var body:some View {HStack(spacing:7){Image("CadenceMarkInk").resizable().scaledToFit().frame(width:38,height:38).accessibilityHidden(true);Text("cadence").font(.system(size:27,weight:.semibold,design:.rounded)).tracking(-1)}.foregroundStyle(Palette.ink)} }
struct SectionLabel:View {let text:String;var body:some View{Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Palette.muted)} }
struct PrimaryButton:ButtonStyle {func makeBody(configuration:Configuration)->some View{configuration.label.font(.headline).frame(maxWidth:.infinity).padding(.vertical,17).background(Palette.ink).foregroundStyle(Palette.paper).clipShape(Capsule()).opacity(configuration.isPressed ? 0.75 : 1)} }

struct PhoneRoot:View {
    @EnvironmentObject var store:PhoneStore
    @State private var showPlayer=false
    var body:some View{
        Group{if store.signedIn{main}else{WelcomeView()}}
            .alert("A little pause",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("OK",role:.cancel){store.error=nil}} message:{Text(store.error ?? "")}
    }
    var main:some View{
        TabView{
            NavigationStack{LibraryView()}.safeAreaInset(edge:.bottom,spacing:0){MiniPlayer(audio:store.audio,onOpen:{showPlayer=true})}.tabItem{Label("Listen",systemImage:"square.grid.2x2")}
            NavigationStack{PhoneDiscoverView()}.safeAreaInset(edge:.bottom,spacing:0){MiniPlayer(audio:store.audio,onOpen:{showPlayer=true})}.tabItem{Label("Discover",systemImage:"sparkles")}.badge(store.discover.newCount)
            NavigationStack{SearchView()}.safeAreaInset(edge:.bottom,spacing:0){MiniPlayer(audio:store.audio,onOpen:{showPlayer=true})}.tabItem{Label("Search",systemImage:"magnifyingglass")}
            NavigationStack{PhoneDownloadsView(downloads:store.downloads)}.safeAreaInset(edge:.bottom,spacing:0){MiniPlayer(audio:store.audio,onOpen:{showPlayer=true})}.tabItem{Label("Downloads",systemImage:"arrow.down.circle")}
            NavigationStack{RunView()}.safeAreaInset(edge:.bottom,spacing:0){MiniPlayer(audio:store.audio,onOpen:{showPlayer=true})}.tabItem{Label("Your run",systemImage:"figure.run")}
        }
        .toolbarBackground(Palette.paper,for:.tabBar).toolbarBackground(.visible,for:.tabBar)
        .sheet(isPresented:$showPlayer){PlayerSheet(audio:store.audio)}
        .task{await store.refresh()}
        .background(Palette.paper)
    }
}
struct WelcomeView:View{
    @EnvironmentObject var store:PhoneStore
    @State private var server=""
    @State private var username=""
    @State private var password=""
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:25){
                Wordmark().padding(.top,24)
                ZStack(alignment:.bottomLeading){
                    RoundedRectangle(cornerRadius:32).fill(Palette.ink)
                    Circle().stroke(Palette.lime.opacity(0.18),lineWidth:52).frame(width:230,height:230).offset(x:165,y:-35)
                    Circle().stroke(Palette.lime.opacity(0.5),lineWidth:2).frame(width:170,height:170).offset(x:145,y:-40)
                    VStack(alignment:.leading,spacing:14){Image(systemName:"figure.run").font(.system(size:34,weight:.light));Text("Your music.\nYour miles.").font(.system(size:43,weight:.medium,design:.serif)).tracking(-1.5);Text("A quieter way to take your\nfavorite music everywhere.").font(.subheadline).foregroundStyle(.white.opacity(0.72))}.foregroundStyle(.white).padding(28)
                }.frame(height:315).clipped().clipShape(RoundedRectangle(cornerRadius:32))
                VStack(alignment:.leading,spacing:15){
                    SectionLabel(text:"Make yourself at home")
                    VStack(alignment:.leading,spacing:8){Text("Server URL").font(.subheadline.weight(.medium));TextField("https://music.example.com",text:$server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding(17).background(.white,in:RoundedRectangle(cornerRadius:16)).accessibilityLabel("Server URL").accessibilityIdentifier("login.server")}
                    TextField("Username",text:$username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().padding(17).background(.white,in:RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("login.username")
                    SecureField("Password",text:$password).textContentType(.password).padding(17).background(.white,in:RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("login.password")
                    Button{Task{await store.login(server:server,username:username,password:password)}}label:{HStack{Text(store.loading ? "Connecting…" : "Let's listen");if store.loading{ProgressView().tint(.white)}else{Image(systemName:"arrow.right")}}}.buttonStyle(PrimaryButton()).disabled(store.loading).accessibilityIdentifier("login.connect")
                    Label("Use your Aurral server's HTTPS address. Connect its VPN if required.",systemImage:"lock.shield").font(.caption).foregroundStyle(Palette.muted)
                    Button("Take a look around · Demo"){store.enterDemo()}.font(.subheadline.weight(.medium)).frame(maxWidth:.infinity).padding(.top,5).accessibilityIdentifier("login.demo")
                }
            }.padding(24)
        }.background(Palette.paper).foregroundStyle(Palette.ink).scrollDismissesKeyboard(.interactively)
    }
}
struct LibraryView:View{
    @EnvironmentObject var store:PhoneStore
    @State private var favorites=false
    @State private var newPlaylist=false
    @State private var importSpotify=false
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:27){
                HStack{Wordmark();Spacer();NavigationLink{SettingsView()}label:{Image(systemName:"person.crop.circle").font(.title2).frame(width:44,height:44)}.accessibilityLabel("Your account").accessibilityIdentifier("account.open");Text(store.isDemo ? "DEMO" : "YOUR LIBRARY").font(.system(size:9,weight:.bold)).tracking(1.5).padding(9).background(.white,in:Capsule())}.padding(.top,12)
                VStack(alignment:.leading,spacing:5){Text("Find your\nrhythm.").font(.system(size:48,weight:.medium,design:.serif)).tracking(-1.8);Text("Good music. A little room to move.").font(.subheadline).foregroundStyle(Palette.muted)}
                NavigationLink{RunView()}label:{RunHero(mix:store.local.mix,confirmed:store.confirmedCount)}.buttonStyle(.plain)
                if store.offline{Label("Offline · saved music is ready",systemImage:"wifi.slash").font(.caption)}

                NavigationLink("Your listening"){ListeningHistoryView(history:store.history,model:store.discover,playback:store.globalPlayback,play:{store.play([$0],position:$1)},playGlobal:store.playGlobal,interaction:CatalogInteraction(history:store.history,playlists:store.playlists,act:{store.catalogAction($0,action:$1,playlistID:$2)},resume:store.resumePrepared,createPlaylist:store.createCatalogPlaylist))}
                NavigationLink("Preparing music · \(store.globalPlayback.pendingCount)"){PreparationListView(center:store.globalPlayback,resume:store.resumePrepared)}
                HStack{SectionLabel(text:"Your playlists");Spacer();Button{newPlaylist=true}label:{Label("New playlist",systemImage:"plus")}.accessibilityIdentifier("playlist.new")}
                Button{importSpotify=true}label:{Label("Import Spotify playlist",systemImage:"square.and.arrow.down")}.accessibilityIdentifier("spotify.open")
                if store.playlistRole==false{Text("Creating or editing playlists requires playlist/Flows permission in Aurral.").font(.caption).foregroundStyle(Palette.muted)}
                if !store.playlists.isEmpty{
                    VStack(alignment:.leading,spacing:14){SectionLabel(text:"Made for your mood");ForEach(store.playlists){playlist in NavigationLink{CollectionView(title:playlist.name,coverID:playlist.coverArt,playlist:playlist,loader:{try await store.songs(for:playlist)})}label:{HStack(spacing:15){Cover(title:playlist.name,data:playlist.coverArt.flatMap{store.artwork[$0]},size:60);VStack(alignment:.leading,spacing:5){Text(playlist.name).font(.headline);Text("\(playlist.songCount ?? 0) tracks").font(.caption).foregroundStyle(Palette.muted)};Spacer();Image(systemName:"arrow.up.right").font(.subheadline)}.foregroundStyle(Palette.ink).padding(12).background(.white,in:RoundedRectangle(cornerRadius:20))}.buttonStyle(.plain).task{await store.loadArt(playlist.coverArt)}}}
                }
                VStack(alignment:.leading,spacing:12){SectionLabel(text:"Your library mix");Button{Task{await store.radio()}}label:{Label("Play a library mix",systemImage:"sparkles")}.buttonStyle(PrimaryButton());Text("Influenced by favorites, followed artists and listening on this device. Plays available library music.").font(.caption).foregroundStyle(Palette.muted);ForEach(store.discovery.prefix(4)){song in SongRow(song:song){store.play(store.discovery,startingAt:song)}}}
                VStack(alignment:.leading,spacing:15){HStack{SectionLabel(text:"On repeat, on purpose");Spacer();Button{favorites=true}label:{Image(systemName:"heart.fill").foregroundStyle(Palette.ink)}}
                    if store.loading && store.albums.isEmpty{ProgressView().frame(maxWidth:.infinity).padding(30)}
                    else if store.albums.isEmpty{ContentUnavailableView("Your first soundtrack",systemImage:"music.note",description:Text("Add music in Aurral, then pull down to refresh."))}
                    else{LazyVGrid(columns:[GridItem(.flexible(),spacing:16),GridItem(.flexible(),spacing:16)],alignment:.leading,spacing:24){ForEach(store.albums){album in NavigationLink{CollectionView(title:album.name,coverID:album.coverArt,loader:{try await store.songs(for:album)})}label:{AlbumTile(album:album)}.buttonStyle(.plain)}}}
                }
                if store.hasMoreAlbums{Button("Load more albums"){Task{await store.loadMoreAlbums()}}.disabled(store.loading).accessibilityIdentifier("library.more")}
                Text("Music for the long way home.").font(.system(.title3,design:.serif)).foregroundStyle(Palette.muted).padding(.vertical,18)
            }.padding(.horizontal,24).padding(.bottom,24)
        }.background(Palette.paper).toolbar(.hidden,for:.navigationBar).refreshable{await store.refresh()}
        .sheet(isPresented:$newPlaylist){PhonePlaylistEditor()}
        .sheet(isPresented:$importSpotify,onDismiss:{Task{await store.refresh()}}){SpotifyImportView(model:store.discover,play:{try await store.playImportedPlaylist($0)},loadSongs:{try await store.songs(for:Playlist(id:$0.subsonicID,name:$0.name))},playSongs:{store.play($0)},refreshLibrary:{await store.refresh()}).id(store.discover.profileID)}
        .navigationDestination(isPresented:$favorites){CollectionView(title:"Your favorites",coverID:nil,loader:{store.favorites})}
    }
}
struct AlbumTile:View{
    @EnvironmentObject var store:PhoneStore
    let album:Album
    var body:some View{
        GeometryReader{geometry in VStack(alignment:.leading,spacing:7){Cover(title:album.name,data:album.coverArt.flatMap{store.artwork[$0]},size:geometry.size.width);Text(album.name).font(.subheadline.weight(.semibold)).lineLimit(1);Text(album.artist ?? "Your library").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)}}.frame(height:210).task{await store.loadArt(album.coverArt)}.foregroundStyle(Palette.ink)
    }
}
struct RunHero:View{
    var mix:RunMix?;var confirmed:Int
    var body:some View{
        HStack(alignment:.top,spacing:14){VStack(alignment:.leading,spacing:13){Label("POCKET-FREE LISTENING",systemImage:"applewatch").font(.system(size:9,weight:.bold)).tracking(1.2);Text(mix?.name ?? "Meet your\nnext run mix.").font(.system(size:28,weight:.semibold,design:.rounded)).tracking(-0.8);Text(mix.map{confirmed == $0.songs.count ? "Ready on your Watch. Go find your miles." : "\(confirmed) of \($0.songs.count) tracks confirmed on Watch"} ?? "Your favorites, ready on your wrist.").font(.caption).fixedSize(horizontal:false,vertical:true)};Spacer(minLength:0);Image(systemName:"figure.run").font(.system(size:62,weight:.ultraLight)).rotationEffect(.degrees(-8)).padding(.top,25)}.padding(23).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(Palette.ink).background(Palette.lime,in:RoundedRectangle(cornerRadius:27))
    }
}
struct SongRow:View{
    @EnvironmentObject var store:PhoneStore
    let song:Song;var onPlay:()->Void
    @State private var addToPlaylist=false
    var body:some View{
        HStack(spacing:12){Button(action:onPlay){HStack(spacing:12){Cover(title:song.title,data:store.art(song),size:48);VStack(alignment:.leading,spacing:4){Text(song.title).font(.subheadline.weight(.medium)).lineLimit(1);Text(song.subtitle).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)};Spacer();Text(song.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)}}.buttonStyle(.plain).accessibilityIdentifier("song.play."+song.id)
            PhoneDownloadButton(song:song,downloads:store.downloads)
            Menu{Button("Play next",systemImage:"text.line.first.and.arrowtriangle.forward"){store.enqueue(song,next:true)};Button("Add to queue",systemImage:"text.badge.plus"){store.enqueue(song)};Button("Add to playlist",systemImage:"music.note.list"){addToPlaylist=true};Button("Play a library mix",systemImage:"sparkles"){Task{await store.radio(song)}};Button{Task{await store.favorite(song)}}label:{Label(store.favorites.contains(where:{$0.id==song.id}) ? "Remove favorite" : "Favorite",systemImage:"heart")};Button{store.prepareMix(name:song.title,songs:[song])}label:{Label("Send to Watch",systemImage:"applewatch")}}label:{Image(systemName:"ellipsis").frame(width:30,height:44)}.accessibilityLabel("Options for \(song.title)")
        }.padding(.vertical,6).foregroundStyle(Palette.ink).task{await store.loadArt(song.coverArt)}.sheet(isPresented:$addToPlaylist){PlaylistPicker(song:song,playlists:store.playlists,add:{try await store.add($0,to:$1)},create:{try await store.savePlaylist(name:$0,songs:$1,original:$2)})}
    }
}
struct CollectionView:View{
    @EnvironmentObject var store:PhoneStore
    let title:String;let coverID:String?;var playlist:Playlist?=nil;let loader:() async throws->[Song]
    @State private var songs:[Song]=[]
    @State private var loading=true
    @State private var error:String?
    @State private var replace=false
    @State private var edit=false
    @State private var delete=false
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        ScrollView{
            VStack(spacing:22){Cover(title:title,data:coverID.flatMap{store.artwork[$0]},size:240).padding(.top,12);VStack(spacing:6){Text(title).font(.system(size:31,weight:.medium,design:.serif)).multilineTextAlignment(.center);Text("\(songs.count) tracks · \(songs.reduce(0){$0+($1.duration ?? 0)}/60) min").font(.caption).foregroundStyle(Palette.muted)}
                HStack(spacing:12){Button{store.play(songs)}label:{Label("Play",systemImage:"play.fill")}.buttonStyle(PrimaryButton());Button{replace=true}label:{Image(systemName:"applewatch.radiowaves.left.and.right").font(.title3).frame(width:58,height:55).background(Palette.lime,in:Capsule())}.accessibilityLabel("Send \(title) to Watch")}.disabled(songs.isEmpty)
                Button{store.download(songs)}label:{Label("Download to iPhone",systemImage:"arrow.down.circle")}.font(.subheadline.weight(.semibold)).disabled(songs.isEmpty)
                if loading{ProgressView().padding()}
                if let error{Text(error).font(.subheadline).foregroundStyle(.secondary)}
                LazyVStack(spacing:2){ForEach(songs){song in SongRow(song:song){store.play(songs,startingAt:song)}}}
                Text("Available from your music library.").font(.caption).foregroundStyle(Palette.muted).padding(.top,12)
            }.padding(24)
        }.background(Palette.paper).foregroundStyle(Palette.ink).navigationBarTitleDisplayMode(.inline)
        .task{do{songs=try await loader()}catch{self.error=error.localizedDescription};loading=false;await store.loadArt(coverID)}
        .toolbar{if let playlist,!playlist.id.hasPrefix("flow:"){Menu{Button("Edit playlist"){edit=true};Button("Delete playlist",role:.destructive){delete=true}}label:{Image(systemName:"ellipsis")}}}
        .sheet(isPresented:$edit,onDismiss:{Task{songs=(try? await loader()) ?? songs}}){PhonePlaylistEditor(playlist:playlist)}
        .confirmationDialog("Delete this playlist?",isPresented:$delete){Button("Delete playlist",role:.destructive){Task{do{if let playlist{try await store.deletePlaylist(playlist);dismiss()}}catch{self.error=error.localizedDescription}}}}
        .confirmationDialog("Make this your Watch mix?",isPresented:$replace,titleVisibility:.visible){Button("Send to Watch"){store.prepareMix(name:title,songs:songs)}}message:{Text(store.bridge.supportsMultipleMixes ? "Adds a saved playlist alongside your other Watch music (up to 10 playlists, 100 tracks each). Starting this sync stops any other incomplete sync; saved playlists remain. You can leave both apps after starting." : "Open the updated Cadence Watch app to keep multiple playlists. Background delivery is scheduled by the system.")}
    }
}
struct SearchView:View{
    @EnvironmentObject var store:PhoneStore
    var body:some View{CatalogSearchView(interaction:CatalogInteraction(history:store.history,playlists:store.playlists,act:{store.catalogAction($0,action:$1,playlistID:$2)},resume:store.resumePrepared,createPlaylist:store.createCatalogPlaylist),model:store.discover,playback:store.globalPlayback,playGlobal:store.playGlobal,fetch:{try await store.searchCatalog($0,kind:$1,offset:$2)},artistAlbums:{try await store.artistAlbums($0)},songRow:{song,songs in AnyView(SongRow(song:song){store.play(songs,startingAt:song)})},albumView:{album in AnyView(CollectionView(title:album.name,coverID:album.coverArt,loader:{try await store.songs(for:album)}))})}
}

struct RunView:View{
    @EnvironmentObject var store:PhoneStore
    var body:some View{RunContent(store:store,bridge:store.bridge,local:store.local)}
}
struct RunContent:View{
    @ObservedObject var store:PhoneStore
    @ObservedObject var bridge:WatchBridge
    @ObservedObject var local:LocalLibrary
    @State private var erase=false
    @State private var switchMix:String?
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:24){SectionLabel(text:"Leave your phone behind");Text("Just you.\nAnd your music.").font(.system(size:42,weight:.medium,design:.serif)).tracking(-1.3)
            if !local.mixes.isEmpty{
                VStack(alignment:.leading,spacing:10){SectionLabel(text:"Saved Watch playlists");ForEach(local.mixes,id:\.id){saved in Button{if store.preparing,local.mix?.id != saved.id{switchMix=saved.id}else{store.selectWatchMix(saved.id)}}label:{HStack{VStack(alignment:.leading){Text(saved.name).font(.headline);Text("\(bridge.receipt(for:saved)?.readyIDs.count ?? 0) / \(saved.songs.count) confirmed on Watch").font(.caption).foregroundStyle(Palette.muted)};Spacer();if local.mix?.id==saved.id{Image(systemName:"checkmark.circle.fill")}}}.buttonStyle(.plain).accessibilityIdentifier("watch.saved."+saved.id)}}
            }
            if !bridge.supportsMultipleMixes{Text("Open the updated Watch app to enable multiple saved playlists.").font(.caption).foregroundStyle(Palette.muted)}
            if let mix=local.mix{
                VStack(alignment:.leading,spacing:18){HStack{Image(systemName:"applewatch").font(.system(size:44,weight:.ultraLight));Spacer();Text("\(mix.durationMinutes) MIN").font(.caption.weight(.bold)).padding(9).background(Palette.paper,in:Capsule())};Text(mix.name).font(.title2.weight(.semibold));ProgressView(value:Double(store.confirmedCount),total:Double(max(1,mix.songs.count))).tint(Palette.ink);Text(store.confirmedCount==mix.songs.count ? "Ready for your run" : "\(store.confirmedCount) of \(mix.songs.count) tracks confirmed on Watch").font(.headline);Text(store.preparing ? store.preparationMessage : "You can leave both apps. Your Watch confirms each saved track; delivery timing depends on watchOS.").font(.caption).foregroundStyle(Palette.muted)
                    if store.confirmedCount==mix.songs.count{Label("Try a quick listen with your iPhone switched off before your first run.",systemImage:"checkmark.seal.fill").font(.caption)}
                    if store.preparing{HStack{Button("Retry Watch sync"){store.retryPreparation()};Spacer();Button("Stop sync",role:.cancel){store.cancelPreparation()}}.font(.subheadline)}else{Button{store.prepareMix(name:mix.name,songs:mix.songs,existing:mix)}label:{Label("Send again",systemImage:"arrow.triangle.2.circlepath")}.buttonStyle(PrimaryButton())}
                }.padding(25).background(Palette.lime,in:RoundedRectangle(cornerRadius:28))
                Label(bridge.status,systemImage:bridge.canTransfer ? "checkmark.circle" : "applewatch.slash").font(.caption).foregroundStyle(Palette.muted)
                if let message=bridge.transferError ?? bridge.receipt?.message{Text(message).font(.caption).foregroundStyle(.orange)}
                VStack(alignment:.leading,spacing:12){SectionLabel(text:"Your running soundtrack");ForEach(mix.songs){song in HStack{VStack(alignment:.leading,spacing:3){Text(song.title).font(.subheadline);Text(song.subtitle).font(.caption).foregroundStyle(Palette.muted)};Spacer();Image(systemName:bridge.receipt(for:mix)?.readyIDs.contains(song.id)==true ? "checkmark.circle.fill" : "clock").foregroundStyle(Palette.muted)}}}
                Button("Remove this Watch mix",role:.destructive){erase=true}.font(.subheadline).padding(.top,10)
            }else{
                VStack(alignment:.leading,spacing:20){Image(systemName:"applewatch.radiowaves.left.and.right").font(.system(size:48,weight:.ultraLight));Text("A soundtrack for\nyour next few miles.").font(.system(.title2,design:.serif));Text("Open an album, a playlist or your favorites, then tap the Watch button. We'll prepare the music here and send it to your wrist.").font(.subheadline).foregroundStyle(Palette.muted);Label(bridge.status,systemImage:"iphone.and.arrow.forward").font(.caption)}.padding(27).background(.white,in:RoundedRectangle(cornerRadius:28))
            }
            VStack(alignment:.leading,spacing:10){SectionLabel(text:"The little pre-run ritual");Label("Connect your iPhone to your music server",systemImage:"1.circle");Label("Keep both devices nearby to transfer",systemImage:"2.circle");Label("Connect earbuds to your Watch and go",systemImage:"3.circle")}.font(.subheadline).foregroundStyle(Palette.muted)
        }.padding(24)}.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("Your run").navigationBarTitleDisplayMode(.inline)
        .task{while !Task.isCancelled{bridge.refresh();try? await Task.sleep(for:.seconds(2))}}
        .confirmationDialog("Switch saved playlists?",isPresented:Binding(get:{switchMix != nil},set:{if !$0{switchMix=nil}})){Button("Stop sync and switch"){if let switchMix{store.selectWatchMix(switchMix)};switchMix=nil}}message:{Text("This stops the current Watch sync. Saved music and independent iPhone downloads remain available.")}
        .confirmationDialog("Remove your current Watch mix?",isPresented:$erase,titleVisibility:.visible){Button("Remove mix",role:.destructive){if let mix=local.mix{store.removeWatchMix(mix)}}}message:{Text("Only this playlist is removed when the Watch next connects. Other saved playlists remain available.")}
    }
}
struct MiniPlayer:View{
    @EnvironmentObject var store:PhoneStore
    @State private var devices=false
    @ObservedObject var audio:AudioController;var onOpen:()->Void
    var body:some View{
        HStack(spacing:10){
            Button{devices=true}label:{Image(systemName:store.playingOnMac ? "laptopcomputer" : "hifispeaker.and.homepod").frame(width:34,height:44)}.accessibilityLabel("Playback devices").accessibilityIdentifier("player.devices")
            if store.playingOnMac{
                VStack(alignment:.leading){Text(store.mac.status.playback?.song?.title ?? "Playing on Mac").font(.subheadline);Text(store.mac.endpoint?.name ?? "Mac").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
                Button{Task{await store.commandMac(PhoneCommand(store.mac.status.playback?.isPlaying==true ? .pause : .play))}}label:{Image(systemName:store.mac.status.playback?.isPlaying==true ? "pause.fill" : "play.fill").frame(width:44,height:44)}.disabled(!store.mac.status.connected)
            }else if let current=audio.current{
                Button(action:onOpen){HStack{Cover(title:current.title,size:40);VStack(alignment:.leading){Text(current.title).font(.subheadline).lineLimit(1);Text(current.subtitle).font(.caption).foregroundStyle(.secondary)};Spacer()}}.buttonStyle(.plain).accessibilityIdentifier("player.open")
                Button{audio.toggle()}label:{Image(systemName:audio.isPlaying ? "pause.fill" : "play.fill").frame(width:44,height:44)}.accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
                Button{audio.next()}label:{Image(systemName:"forward.end.fill").frame(width:36,height:44)}.accessibilityLabel("Next track")
            }else{Text("Choose music to play").font(.caption).foregroundStyle(.secondary);Spacer()}
        }.padding(.horizontal,15).padding(.vertical,8).background(Palette.paper).overlay(alignment:.top){Divider()}.sheet(isPresented:$devices){PlaybackDevicesView(client:store.mac)}
    }
}
struct PlayerSheet:View{
    @State private var queue=false
    @EnvironmentObject var store:PhoneStore
    @ObservedObject var audio:AudioController
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        VStack(spacing:25){HStack{Button{dismiss()}label:{Image(systemName:"chevron.down").frame(width:44,height:44)}.accessibilityLabel("Close player");Spacer();SectionLabel(text:"A moment for the music");Spacer();Button{queue=true}label:{Image(systemName:"list.bullet").frame(width:44,height:44)}.accessibilityLabel("Open queue")}
            Spacer(minLength:0)
            if let current=audio.current{
                Cover(title:current.title,data:store.art(current),size:285).shadow(color:Palette.ink.opacity(0.15),radius:25,y:15)
                VStack(spacing:8){Text(current.title).font(.system(size:30,weight:.medium,design:.serif)).multilineTextAlignment(.center);Text(current.subtitle).font(.subheadline).foregroundStyle(Palette.muted)}
                VStack(spacing:5){Slider(value:Binding(get:{min(audio.elapsed,max(audio.duration,1))},set:{audio.seek($0)}),in:0...max(audio.duration,1)).tint(Palette.ink).accessibilityLabel("Playback position");HStack{Text(time(audio.elapsed));Spacer();Text(time(audio.duration))}.font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)}
                HStack(spacing:24){Button{audio.shuffle()}label:{Image(systemName:"shuffle").foregroundStyle(audio.isShuffled ? Palette.ink : Palette.muted)}.accessibilityLabel("Shuffle");Button{audio.previous()}label:{Image(systemName:"backward.end.fill").font(.title2)}.accessibilityLabel("Previous track");Button{audio.toggle()}label:{Image(systemName:audio.isPlaying ? "pause.fill" : "play.fill").font(.title).frame(width:76,height:76).background(Palette.lime,in:Circle())}.accessibilityLabel(audio.isPlaying ? "Pause" : "Play");Button{audio.next()}label:{Image(systemName:"forward.end.fill").font(.title2)}.accessibilityLabel("Next track");Button{audio.cycleRepeat()}label:{Image(systemName:audio.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(audio.repeats ? Palette.ink : Palette.muted)}.accessibilityLabel(audio.repeatMode.label)}
                if let error=audio.error{VStack{Text(error).font(.caption).foregroundStyle(.orange);HStack{Button("Retry"){audio.retryCurrent()};Button("Skip"){audio.next()}}}}
                HStack{Button{Task{await store.favorite(current)}}label:{Label(store.favorites.contains(where:{$0.id==current.id}) ? "In your favorites" : "Save a little favorite",systemImage:store.favorites.contains(where:{$0.id==current.id}) ? "heart.fill" : "heart")}.font(.subheadline);Spacer(minLength:12);PhoneDownloadButton(song:current,downloads:store.downloads)}.padding(.horizontal,18)
            }
            Spacer(minLength:0)
        }.padding(26).background(Palette.paper).foregroundStyle(Palette.ink).presentationDragIndicator(.visible).sheet(isPresented:$queue){QueueView(audio:audio)}.onChange(of:store.playingOnMac){_,value in if value{dismiss()}}
    }
    func time(_ seconds:Double)->String{let value=max(0,Int(seconds.isFinite ? seconds : 0));return String(format:"%d:%02d",value/60,value%60)}
}
struct SettingsView:View{
    @EnvironmentObject var store:PhoneStore
    @State private var signOut=false
    var body:some View{
        List{
            Section{HStack(spacing:15){Image(systemName:"person.crop.circle.fill").font(.system(size:46)).foregroundStyle(Palette.ink);VStack(alignment:.leading,spacing:4){Text(store.username).font(.headline);Text(store.isDemo ? "An original little demo soundtrack" : "Your own library. Your own pace.").font(.caption).foregroundStyle(Palette.muted)}}.padding(.vertical,12)}
            Section("Your music"){Label("Your Aurral server",systemImage:"lock.shield");if let server=store.credentials?.server{Link("Open Aurral",destination:server)};Text("Search All music or import a Spotify playlist in Cadence. Your Aurral server prepares missing audio through its configured sources.").font(.caption).foregroundStyle(Palette.muted)}
            Section("Ready for the outdoors"){Text("Your iPhone downloads music from your server, then sends the files to your Watch. Once every track is confirmed ready, the Watch plays offline without your phone.").font(.subheadline);Text("Start the Watch sync, then leave both apps if you like. Downloads and transfers continue when the system allows; keeping the devices nearby and charging helps.").font(.caption).foregroundStyle(Palette.muted)}
            Section("Mac playback"){MacConnectionView(client:store.mac,discovery:store.macDiscovery)}
            Section("About Cadence"){Wordmark().padding(.vertical,8);Text("A little music. A lot of miles.").font(.system(.headline,design:.serif));Text("Version \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1") · Built for your next run").font(.caption).foregroundStyle(Palette.muted);Text("No analytics or advertising. Server credentials stay in this iPhone's Keychain. External catalog and server integrations use their own services. Demo music is composed and generated for Cadence.").font(.caption).foregroundStyle(Palette.muted)}
            Section{Button(store.isDemo ? "Leave demo" : "Sign out",role:.destructive){signOut=true}}
        }.scrollContentBackground(.hidden).background(Palette.paper).navigationTitle("Your corner").toolbar(.visible,for:.navigationBar)
        .confirmationDialog("Sign out of Cadence?",isPresented:$signOut,titleVisibility:.visible){Button("Sign out",role:.destructive){store.logout()}}message:{Text("Downloaded music is removed from this iPhone. The Watch receives an erase request when it next connects; you can also erase directly on the Watch.")}
    }
}

struct PhonePlaylistEditor:View {
    @EnvironmentObject var store:PhoneStore
    var playlist:Playlist?
    var body:some View{PlaylistEditor(original:playlist,load:{try await store.playlistForEditing($0)},search:{try await store.search($0).song ?? []},save:{try await store.savePlaylist(name:$0,songs:$1,original:$2)})}
}

struct PhoneDiscoverView:View {
    @EnvironmentObject var store:PhoneStore
    var body:some View{DiscoverView(model:store.discover,pauseMain:{store.audio.pause()},playFromLibrary:{try await store.playDiscovery($0,artist:$1)})}
}
