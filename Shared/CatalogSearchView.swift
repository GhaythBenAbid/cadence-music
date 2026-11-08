#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

/// Search offsets count server rows, not deduplicated UI rows.
@MainActor final class CatalogSearchState:ObservableObject {
    @Published var songs:[Song]=[]
    @Published var artists:[Artist]=[]
    @Published var albums:[Album]=[]
    @Published var loading=false
    @Published var error:String?
    @Published var hasMore=false
    private var offset=0
    private var stamp=UUID()
    func reset(){stamp=UUID();songs=[];artists=[];albums=[];offset=0;hasMore=false;error=nil;loading=false}
    func load(query:String,kind:SearchKind,fetch:(String,SearchKind,Int)async throws->SearchResults)async{
        guard !loading,!query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        let token=stamp;loading=true;error=nil
        defer{if token==stamp{loading=false}}
        do{
            let value=try await fetch(query,kind,offset);try Task.checkCancellation();guard token==stamp else{return}
            let count=kind.count(value);offset+=count;hasMore=count==30
            var seen=Set(songs.map(\.id));songs += (value.song ?? []).filter{seen.insert($0.id).inserted}
            seen=Set(artists.map(\.id));artists += (value.artist ?? []).filter{seen.insert($0.id).inserted}
            seen=Set(albums.map(\.id));albums += (value.album ?? []).filter{seen.insert($0.id).inserted}
        }catch is CancellationError{}catch{if token==stamp{self.error="Search couldn't refresh. Check your server connection and retry. Loaded results remain available."}}
    }
}
struct CatalogSearchView:View {
    let interaction:CatalogInteraction
    let model:DiscoveryModel
    @ObservedObject var playback:PreparationCenter
    let playGlobal:(MusicCatalogEntry)->Void
    let fetch:(String,SearchKind,Int)async throws->SearchResults
    let artistAlbums:(Artist)async throws->[Album]
    let songRow:(Song,[Song])->AnyView
    let albumView:(Album)->AnyView
    @StateObject private var state=CatalogSearchState()
    @FocusState private var searchFocused:Bool
    @State private var allMusic=true
    @State private var globalResults:[MusicCatalogEntry]=[]
    @State private var globalLoading=false
    @State private var globalError:String?
    @State private var shown=30
    @State private var query=""
    @State private var kind:SearchKind = .songs
    var body:some View{
        List{
            GlobalPlaybackStatusView(state:playback)
            NavigationLink("Preparing music · \(playback.pendingCount)"){PreparationListView(center:playback,resume:interaction.resume)}
            Section{
                Picker("Search in",selection:$allMusic){Text("All music").tag(true);Text("My library").tag(false)}.pickerStyle(.segmented).accessibilityIdentifier("search.scope")
                Picker("Search for",selection:$kind){ForEach(SearchKind.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
                Text(allMusic ? "Find songs beyond your library. Play prepares missing audio through Aurral; availability and waiting time vary." : "Search music already available in your library.").font(.caption).foregroundStyle(.secondary)
            }
            if query.isEmpty{ContentUnavailableView("Find your next favorite",systemImage:"magnifyingglass",description:Text("Search songs, artists or albums."))}
            if allMusic{
                GlobalCatalogRows(entries:Array(globalResults.prefix(shown)),model:model,playback:playback,play:playGlobal,interaction:interaction)
                if shown<globalResults.count{Button("Load more "+kind.rawValue.lowercased()){shown+=30}}
                if globalLoading{ProgressView("Searching all music…")}
                if let globalError{Text(globalError);Button("Retry catalog search"){Task{await loadGlobal()}}}
                if query.count>=2,!globalLoading,globalError==nil,globalResults.isEmpty{Text("No matching "+kind.rawValue.lowercased()+" in this catalog. Try the title and artist, or another spelling.")}
            }else{
            if let error=state.error{Section{Text(error).foregroundStyle(.secondary);Button("Retry search"){Task{await load()}}}}
            switch kind{
            case .songs:ForEach(state.songs){song in songRow(song,state.songs)}
            case .artists:ForEach(state.artists){artist in NavigationLink{ArtistAlbumsView(artist:artist,loader:{try await artistAlbums(artist)},albumView:albumView)}label:{Label(artist.name,systemImage:"person.crop.circle")}}
            case .albums:ForEach(state.albums){album in NavigationLink{albumView(album)}label:{VStack(alignment:.leading){Text(album.name);Text(album.artist ?? "Unknown artist").font(.caption).foregroundStyle(.secondary)}}}
            }
            if state.loading{ProgressView("Searching…")}
            else if state.hasMore{Button("Load more "+kind.rawValue.lowercased()){Task{await load()}}.accessibilityIdentifier("search.more")}
            else if !query.isEmpty && state.error==nil && state.songs.isEmpty && state.artists.isEmpty && state.albums.isEmpty{Text("No matching "+kind.rawValue.lowercased()+" in your library.").foregroundStyle(.secondary)}
            }
        }.navigationTitle("Search").searchable(text:$query,prompt:allMusic ? "Search all music" : "Search your library")
        #if os(iOS)
        .searchFocused($searchFocused).onSubmit(of:.search){searchFocused=false}
        #endif
        .task(id:query+"|"+kind.rawValue+"|"+String(allMusic)+"|"+model.profileID){state.reset();globalResults=[];globalError=nil;shown=30;globalLoading=allMusic && query.count>=2;do{try await Task.sleep(for:.milliseconds(allMusic ? 700 : 300));try Task.checkCancellation();if allMusic{await loadGlobal()}else{await load()}}catch{}}
    }
    private func loadGlobal()async{
        guard query.trimmingCharacters(in:.whitespacesAndNewlines).count>=2 else{globalLoading=false;return};let identity=model.profileID,term=query,selected=kind;globalLoading=true;globalError=nil
        do{let result=try await model.globalSearch(term,kind:selected);try Task.checkCancellation();guard term==query,selected==kind,allMusic,identity==model.profileID else{return};globalResults=result;globalLoading=false}catch is CancellationError{}catch{guard term==query,selected==kind,allMusic,identity==model.profileID else{return};globalError="Global search couldn’t load. Check your internet connection and retry.";globalLoading=false}
    }
    private func load()async{await state.load(query:query,kind:kind,fetch:fetch)}
}
private struct ArtistAlbumsView:View {
    let artist:Artist
    let loader:()async throws->[Album]
    let albumView:(Album)->AnyView
    @State private var albums:[Album]=[]
    @State private var loading=true
    @State private var error:String?
    var body:some View{List{
        if loading{ProgressView("Loading albums…")}
        if let error{Text(error);Button("Retry"){Task{await load()}}}
        ForEach(albums){album in NavigationLink{albumView(album)}label:{VStack(alignment:.leading){Text(album.name);if let year=album.year{Text(String(year)).font(.caption).foregroundStyle(.secondary)}}}.accessibilityIdentifier("artist.album."+album.id)}
        if !loading && albums.isEmpty && error==nil{Text("No available albums for this artist.")}
    }.navigationTitle(artist.name).task{await load()}}
    private func load()async{loading=true;error=nil;defer{loading=false};do{albums=try await loader()}catch{self.error="This artist couldn't load. Check your server connection and retry."}}
}
#endif
