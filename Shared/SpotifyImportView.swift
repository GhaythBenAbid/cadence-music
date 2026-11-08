#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

struct SpotifyImportView:View {
    @ObservedObject var model:DiscoveryModel
    @ObservedObject private var state:SpotifyImportState
    let play:(ImportedPlaylist)async throws->Bool
    let loadSongs:(ImportedPlaylist)async throws->[Song]
    let playSongs:([Song])->Void
    let refreshLibrary:()async->Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var link=""
    @State private var name=""
    @State private var sync=false
    @State private var phase:String?
    @State private var preview:SpotifyImportPreview?
    @State private var previewID:String?
    @State private var error:String?
    @State private var notice:String?
    @State private var submitted=false
    private var busy:Bool{phase != nil}
    init(model:DiscoveryModel,play:@escaping(ImportedPlaylist)async throws->Bool,loadSongs:@escaping(ImportedPlaylist)async throws->[Song],playSongs:@escaping([Song])->Void,refreshLibrary:@escaping()async->Void){
        self.model=model;self.state=model.imports;self.play=play;self.loadSongs=loadSongs;self.playSongs=playSongs;self.refreshLibrary=refreshLibrary
    }
    var body:some View {
        NavigationStack{
            Form{
                Section{
                    Label("Aurral account: "+model.accountName,systemImage:"person.crop.circle")
                    Text("Imports belong to this Aurral account. Spotify provides the track list; Aurral prepares available audio.").font(.caption).foregroundStyle(.secondary)
                    if model.isDemo{Text("Demo preview only. No real import is made.").font(.caption)}
                }
                results
                Section("Import another playlist"){
                    Text("Spotify playlist link").font(.caption).foregroundStyle(.secondary)
                    TextField("https://open.spotify.com/playlist/…",text:$link).labelsHidden().textFieldStyle(.roundedBorder).accessibilityIdentifier("spotify.link")
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        #endif
                    Button("Check playlist"){let source=link;perform("Reading Spotify playlist…"){
                        preview=try await model.spotifyPreview(source);previewID=SpotifyPlaylistLink.id(source);submitted=false;if name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{name="Spotify playlist · "+Date().formatted(.dateTime.day().month(.abbreviated).hour().minute().second())};notice="Playlist found. Tap Import playlist below. You can change its suggested name."
                    }}.disabled(busy || state.connection?.connected != true || SpotifyPlaylistLink.id(link)==nil).accessibilityIdentifier("spotify.preview")
                    if !link.isEmpty && SpotifyPlaylistLink.id(link)==nil{Text("Paste a full Spotify playlist link. Track, album and shortened links aren't supported.").font(.caption).foregroundStyle(.secondary)}
                    if state.connection?.connected != true{Text("Connect Spotify below to check a new playlist. Existing imported audio remains playable.").font(.caption).foregroundStyle(.secondary)}
                }.disabled(busy)
                if let preview,previewID==SpotifyPlaylistLink.id(link){
                    Section("Playlist preview"){
                        Text("\(preview.trackCount) tracks · \(preview.skipped) skipped").accessibilityIdentifier("spotify.track-count")
                        ForEach(Array(preview.previewTracks.enumerated()),id:\.offset){_,track in VStack(alignment:.leading){Text(track.trackName);Text(track.artistName).font(.caption).foregroundStyle(.secondary)}}
                        VStack(alignment:.leading,spacing:6){Text("Playlist name").font(.caption).foregroundStyle(.secondary);TextField("My favorites",text:$name).labelsHidden().textFieldStyle(.roundedBorder).accessibilityIdentifier("spotify.name")}
                        Toggle("Check for new tracks daily",isOn:$sync)
                        if sync{Text("Checks every 24 hours. Removed Spotify songs stay in this playlist.").font(.caption)}
                        if name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{Text("Enter a playlist name to enable Import.").font(.caption).foregroundStyle(.secondary)}
                        Button("Import playlist"){
                            perform("Sending import to Aurral…"){
                                let receipt=try await model.importSpotify(link,name:name,sync:sync)
                                guard receipt.success else{throw SpotifyImportError.uncertain}
                                submitted=true;state.acceptedName=name.trimmingCharacters(in:.whitespacesAndNewlines);state.acceptedCount=receipt.tracksQueued
                                notice=nil;await reload();await refreshLibrary()
                            }
                        }.disabled(busy || submitted || model.isDemo || preview.trackCount==0 || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("spotify.import")
                    }.disabled(busy)
                }
                Section("Spotify connection"){
                    Label(state.connection?.connected==true ? "Spotify connected" : "Spotify connection needed",systemImage:state.connection?.connected==true ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                    if let server=model.server{Link("Connect or manage Spotify in Aurral",destination:server.appendingPathComponent("library/playlists"))}
                    Button("Check connection again"){Task{await reload()}}.disabled(busy || state.checking)
                }
            }
            .navigationTitle("Import from Spotify")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}
            .safeAreaInset(edge:.top,spacing:0){feedback}
            .refreshable{await reload()}
        }
        #if os(macOS)
        .formStyle(.grouped).frame(minWidth:540,minHeight:650)
        #endif
        .onChange(of:link){_,_ in preview=nil;previewID=nil;submitted=false;notice=nil;error=nil}
        .onChange(of:state.revision){_,_ in Task{await refreshLibrary()}}
        .task{await reload();while !Task.isCancelled{do{try await Task.sleep(for:.seconds(10))}catch{return};if scenePhase == .active && !busy{await reload(quiet:true)}}}
        .onChange(of:scenePhase){_,value in if value == .active{Task{await reload()}}}
    }
    @ViewBuilder private var feedback:some View{
        if busy || state.checking || state.acceptedName != nil || notice != nil || error != nil || state.statusError != nil || state.connectionError != nil {
        VStack(alignment:.leading,spacing:8){
            if let phase{ProgressView(phase).accessibilityIdentifier("spotify.progress")}
            else if state.checking{ProgressView("Refreshing imports…")}
            if let accepted=state.acceptedName{
                Label("\(accepted) · \(state.acceptedCount) tracks submitted",systemImage:"checkmark.circle").font(.subheadline.weight(.semibold)).accessibilityIdentifier("spotify.accepted")
                if !(state.status?.spotifyPlaylists.contains{$0.name==accepted} ?? false){Text("Aurral accepted the import. Waiting for the playlist to appear…").font(.caption)}
            }
            if let notice{Text(notice).font(.callout).accessibilityIdentifier("spotify.notice")}
            if let failure=error ?? state.statusError ?? state.connectionError{
                Label(failure,systemImage:"exclamationmark.circle").font(.caption).accessibilityIdentifier("spotify.error")
                if state.status != nil{Text("Last loaded results remain visible.").font(.caption).foregroundStyle(.secondary)}
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.vertical,10).background(.regularMaterial)
        }
    }
    @ViewBuilder private var results:some View{
        Section("Your imported playlists"){
            if let status=state.status{
                if status.spotifyPlaylists.isEmpty{
                    Text("No Spotify imports for this account yet. Paste a link below to start.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(status.spotifyPlaylists){playlist in
                    VStack(alignment:.leading,spacing:10){
                        NavigationLink{
                            ImportedSongsView(playlist:playlist,stats:status.sharedPlaylistStats[playlist.id],load:{if model.isDemo{return DemoLibrary.songs};return try await loadSongs(playlist)},play:playSongs)
                        }label:{Label(playlist.name,systemImage:"music.note.list").font(.headline).accessibilityIdentifier("spotify.playlist."+playlist.id)}
                        if let stats=status.sharedPlaylistStats[playlist.id]{
                            ProgressView(value:Double(stats.done),total:Double(max(playlist.trackCount,stats.total,1)))
                            Text("\(stats.done) ready of \(playlist.trackCount) · \(stats.pending + stats.downloading) preparing").font(.subheadline)
                            if stats.blocked + stats.failed > 0{Text("\(stats.blocked) blocked · \(stats.failed) failed. These songs need attention in Aurral.").font(.caption).foregroundStyle(.secondary)}
                        }
                        Button("Play available tracks",systemImage:"play.fill"){perform("Loading playable songs…"){
                            notice=try await play(playlist) ? "Playing "+playlist.name : "No playable audio yet. Open the playlist to refresh its songs, or check Aurral for source failures."
                        }}.disabled(busy || state.status?.sharedPlaylistStats[playlist.id]?.done==0)
                        if let server=model.server{Link("Review unavailable tracks in Aurral",destination:server.appendingPathComponent("library/playlists").appendingPathComponent(playlist.id)).font(.caption)}
                    }.padding(.vertical,8)
                }
            }else if !state.checking{Text("Imports couldn't load. Refresh to retry; any error is shown above.").font(.callout)}
            if let date=state.updatedAt{Text("Updated "+date.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
            Button("Refresh imports"){Task{await reload();await refreshLibrary()}}.disabled(busy || state.checking)
        }
    }
    @MainActor private func perform(_ title:String,_ action:@escaping()async throws->Void){Task{
        guard !busy else{return};phase=title;error=nil
        defer{phase=nil}
        do{try await action()}catch is CancellationError{}catch{self.error=(error as? SpotifyImportError)?.localizedDescription ?? "Aurral couldn't complete this request. Check your server connection and retry."}
    }}
    @MainActor private func reload(quiet:Bool=false)async{
        await state.reload(quiet:quiet,connection:{try await model.spotifyConnection()},imports:{try await model.spotifyImports()})
    }
}

private struct ImportedSongsView:View {
    let playlist:ImportedPlaylist
    let stats:PlaylistImportStats?
    let load:()async throws->[Song]
    let play:([Song])->Void
    @State private var songs:[Song]=[]
    @State private var loading=true
    @State private var error:String?
    var body:some View{
        List{
            Section{
                Text("\(songs.count) songs ready to play · \(playlist.trackCount) tracks requested").font(.headline)
                if let stats,stats.failed + stats.blocked > 0{Text("\(stats.failed + stats.blocked) tracks need attention in Aurral. Only available full audio is listed below.").font(.caption).foregroundStyle(.secondary)}
                Button("Play all available",systemImage:"play.fill"){play(songs)}.disabled(songs.isEmpty)
                Button("Refresh songs"){Task{await refresh()}}.disabled(loading)
            }
            if loading{ProgressView("Loading available songs…")}
            if let error{Text(error).foregroundStyle(.secondary)}
            if !loading && songs.isEmpty{Text("No playable audio yet. Aurral may still be preparing songs or its sources couldn't find them.")}
            ForEach(Array(songs.enumerated()),id:\.offset){index,song in
                Button{play(Array(songs[index...]))}label:{HStack{Image(systemName:"play.circle");VStack(alignment:.leading){Text(song.title);Text(song.artist ?? "Unknown artist").font(.caption).foregroundStyle(.secondary)}}}.buttonStyle(.plain)
            }
        }.navigationTitle(playlist.name).task{await refresh()}.refreshable{await refresh()}
    }
    @MainActor private func refresh()async{loading=true;error=nil;defer{loading=false};do{songs=try await load()}catch{self.error="Songs couldn't refresh. Check your server connection and try again."}}
}
#endif
