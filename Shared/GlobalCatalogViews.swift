#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

struct CatalogInteraction {
    let history:ListeningHistory
    let playlists:[Playlist]
    let act:([MusicCatalogEntry],CatalogAction,String?)->Void
    let resume:(String)->Void
    var createPlaylist:((String)async throws->Playlist)?=nil
}
struct GlobalCatalogRows:View {
    let entries:[MusicCatalogEntry]
    let model:DiscoveryModel
    let playback:PreparationCenter
    let play:(MusicCatalogEntry)->Void
    var interaction:CatalogInteraction?=nil
    @State private var playlistEntries:[MusicCatalogEntry]=[]
    @State private var choosingPlaylist=false
    var body:some View{
        ForEach(entries){entry in
            if entry.kind == .song{
                HStack{
                    Button{play(entry)}label:{HStack{Image(systemName:"play.fill");VStack(alignment:.leading){Text(entry.title);Text(entry.artist+" · "+(entry.album ?? "Song")).font(.caption).foregroundStyle(.secondary)};Spacer()}}.buttonStyle(.plain).accessibilityLabel("Play "+entry.title).accessibilityIdentifier("catalog.play."+entry.id)
                    if let interaction{
                        Menu{
                            Button("Play next"){interaction.act([entry],.playNext,nil)}
                            Button("Add to queue"){interaction.act([entry],.enqueue,nil)}
                            Button(interaction.history.profile.savedCatalog.contains(where:{$0.id==entry.id}) ? "Saved to favorites" : "Save to favorites"){interaction.act([entry],.favorite,nil)}.disabled(interaction.history.profile.savedCatalog.contains(where:{$0.id==entry.id}))
                            Button("Add to playlist"){playlistEntries=[entry];choosingPlaylist=true}
                            Button("Download when ready"){interaction.act([entry],.download,nil)}
                        }label:{Image(systemName:"ellipsis")}.accessibilityLabel("Options for "+entry.title)
                    }
                    if let url=entry.link{Link(destination:url){Image(systemName:"arrow.up.right")}.help("View in Apple Music").accessibilityLabel("View "+entry.title+" in Apple Music")}
                }
            }else{
                NavigationLink{GlobalCatalogDetail(entry:entry,model:model,playback:playback,play:play,interaction:interaction)}label:{HStack{Image(systemName:entry.kind == .artist ? "person.crop.circle" : "square.stack");VStack(alignment:.leading){Text(entry.title);if entry.kind == .album{Text(entry.artist).font(.caption).foregroundStyle(.secondary)}}}}
            }
        }.sheet(isPresented:$choosingPlaylist){if let interaction{CatalogPlaylistPicker(entries:playlistEntries,interaction:interaction)}}
    }
}
struct GlobalCatalogDetail:View {
    let entry:MusicCatalogEntry
    let model:DiscoveryModel
    let playback:PreparationCenter
    let play:(MusicCatalogEntry)->Void
    var interaction:CatalogInteraction?=nil
    @State private var choosingPlaylist=false
    @State private var entries:[MusicCatalogEntry]=[]
    @State private var error:String?
    @State private var loading=true
    @State private var shown=30
    var body:some View{List{
        GlobalPlaybackStatusView(state:playback)
        if let interaction{NavigationLink("Preparing music · \(playback.pendingCount)"){PreparationListView(center:playback,resume:interaction.resume)}}
        if let url=entry.link{Link("View in Apple Music",destination:url)}
        Text(entry.kind == .artist ? "Catalog albums. Open one to browse its songs." : "Play uses a library copy when available, or asks Aurral to prepare it. Preparation can take time or fail.").font(.caption).foregroundStyle(.secondary)
        if let interaction{
            if entry.kind == .artist{Button(interaction.history.profile.followedArtists.contains(where:{$0.id==entry.id}) ? "Unfollow artist" : "Follow artist"){interaction.history.follow(entry)}}
            else{HStack{Button("Play album"){interaction.act(entries,.play,nil)}.disabled(entries.isEmpty);Menu("More"){
                Button("Play album next"){interaction.act(entries,.playNext,nil)}
                Button("Add album to queue"){interaction.act(entries,.enqueue,nil)}
                Button("Save album to favorites"){interaction.act(entries,.favorite,nil)}
                Button("Add album to playlist"){choosingPlaylist=true}
                Button("Download album when ready"){interaction.act(entries,.download,nil)}
            }.disabled(entries.isEmpty)}}
        }
        GlobalCatalogRows(entries:Array(entries.prefix(shown)),model:model,playback:playback,play:play,interaction:interaction)
        if shown<entries.count{Button("Load more"){shown+=30}}
        if loading{ProgressView("Loading catalog…")}
        if let error{Text(error);Button("Retry"){Task{await load()}}}
        if !loading,error==nil,entries.isEmpty{Text("No catalog results available.")}
    }.navigationTitle(entry.title).task{await load()}.sheet(isPresented:$choosingPlaylist){if let interaction{CatalogPlaylistPicker(entries:entries,interaction:interaction)}}}
    private func load()async{loading=true;error=nil;defer{loading=false};do{let value=try await model.globalChildren(entry);try Task.checkCancellation();entries=value}catch is CancellationError{}catch{self.error="The catalog couldn't load. Check your connection and retry."}}
}
struct CatalogPlaylistPicker:View {
    let entries:[MusicCatalogEntry]
    let interaction:CatalogInteraction
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var busy=false
    @State private var error:String?
    var body:some View{NavigationStack{List{
        Text("Missing songs will be prepared and added as they become available. Existing tracks are kept once.").font(.caption).foregroundStyle(.secondary)
        if let create=interaction.createPlaylist{Section("New playlist"){
            TextField("Playlist name",text:$name).accessibilityIdentifier("catalog.playlist.name")
            Button("Create and prepare songs"){Task{busy=true;error=nil;defer{busy=false};do{let playlist=try await create(name);interaction.act(entries,.playlist,playlist.id);dismiss()}catch{self.error=error.localizedDescription}}}.disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("catalog.playlist.create")
        }}
        if let error{Text(error).foregroundStyle(.orange)}
        ForEach(interaction.playlists.filter{!$0.id.hasPrefix("flow:")}){playlist in Button(playlist.name){interaction.act(entries,.playlist,playlist.id);dismiss()}}
        if interaction.playlists.isEmpty && interaction.createPlaylist==nil{Text("Create a playlist from Listen first.")}
    }.disabled(busy).navigationTitle("Add to playlist").toolbar{Button("Cancel"){dismiss()}}}}
}
struct GlobalPlaybackStatusView:View {
    @ObservedObject var state:PreparationCenter
    var body:some View{if let message=state.message{Section{
        if let track=state.track{Text(track.title+" · "+track.artist).font(.headline)}
        Text(message).font(.callout).foregroundStyle(.secondary)
        if state.waiting{ProgressView();Button("Stop waiting"){state.stopWaiting()}}
    }}}
}
#endif
