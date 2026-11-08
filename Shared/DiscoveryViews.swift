#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

private enum DiscoverPalette {
    static let paper=Color(red:245/255,green:243/255,blue:235/255)
    static let ink=Color(red:22/255,green:33/255,blue:29/255)
    static let lime=Color(red:215/255,green:245/255,blue:103/255)
}
struct DiscoverArtwork:View {
    let title:String
    var source:String?
    var server:URL?
    var size:CGFloat=140
    var circular=false
    private var url:URL?{guard let server else{return nil};return DiscoveryLinks.media(source,server:server)}
    var body:some View{
        ZStack{
            LinearGradient(colors:[DiscoverPalette.ink,Color(red:0.35,green:0.54,blue:0.42)],startPoint:.topLeading,endPoint:.bottomTrailing)
            Text(String(title.prefix(1))).font(.system(size:size*0.4,weight:.medium,design:.serif)).foregroundStyle(DiscoverPalette.lime)
            if let url{AsyncImage(url:url){phase in if let image=phase.image{image.resizable().scaledToFill()}}}
        }.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:circular ? size/2 : 18)).accessibilityHidden(true)
    }
}
struct DiscoverView:View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible=false
    @ObservedObject var model:DiscoveryModel
    var pauseMain:()->Void
    var playFromLibrary:(DiscoverTrack,String)async throws->Bool
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:28){
                HStack(alignment:.top){VStack(alignment:.leading,spacing:7){Text("A little discovery.").font(.system(size:38,weight:.medium,design:.serif)).tracking(-1);Text("New releases. New favorites. Your next obsession.").font(.subheadline).foregroundStyle(.secondary)};Spacer();Button{Task{await model.refresh(force:true);model.markSeen()}}label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("Refresh discoveries").disabled(model.loading)}
                if model.isDemo{Label("Demo discoveries · original Cadence music",systemImage:"sparkles").font(.caption)}
                if let error=model.error{Label(error,systemImage:"wifi.exclamationmark").font(.caption).foregroundStyle(.secondary)}
                if model.loading && model.snapshot==nil{ProgressView("Finding your next favorite…").frame(maxWidth:.infinity).padding(40)}
                if let snapshot=model.snapshot{
                    releases(snapshot.releases.filter{!$0.upcoming()},title:"New releases")
                    artists(snapshot.response.recommendations,title:"For you",subtitle:"Artists to explore, based on your Aurral taste.")
                    releases(snapshot.releases.filter{$0.upcoming()}.sorted{($0.releaseDate ?? "")<($1.releaseDate ?? "")},title:"Coming soon")
                    if !snapshot.playlists.isEmpty{
                        VStack(alignment:.leading,spacing:13){heading("Fresh playlists");ScrollView(.horizontal,showsIndicators:false){HStack(alignment:.top,spacing:18){ForEach(snapshot.playlists.prefix(12),id:\.listID){playlist in NavigationLink{DiscoverTracksView(model:model,title:playlist.name,artist:"",webURL:model.server?.appendingPathComponent("discover/playlists").appendingPathComponent(playlist.browseProvider).appendingPathComponent(playlist.id),pauseMain:pauseMain,playFromLibrary:playFromLibrary,loader:{try await model.tracks(playlist:playlist)})}label:{VStack(alignment:.leading,spacing:7){DiscoverArtwork(title:playlist.name,source:playlist.artworkUrl,server:model.server);Text(playlist.name).font(.headline).lineLimit(2);Text(playlist.curator ?? "Editorial picks").font(.caption).foregroundStyle(.secondary).lineLimit(2)}}.buttonStyle(.plain).frame(width:140)}}}}
                    }
                    artists(Array(snapshot.response.globalTop.prefix(16)),title:"Trending artists",subtitle:"What listeners are exploring right now.")
                    if snapshot.releases.isEmpty{VStack(alignment:.leading,spacing:8){heading("New releases");Text("No recent releases are listed yet. Aurral updates its release calendar for library and recommended artists; check back after it refreshes.").font(.subheadline).foregroundStyle(.secondary)}}
                    if snapshot.response.recommendations.isEmpty{Text("Aurral is building your recommendations. Favorites and your existing library help shape them.").font(.subheadline).foregroundStyle(.secondary)}
                    Text("Discovery finds music beyond your library. Previews are short samples; full playback uses music available in your library. Open an item in Aurral to check availability and manage additions.").font(.caption).foregroundStyle(.secondary)
                }else if !model.loading{ContentUnavailableView("Discover your next favorite",systemImage:"sparkles",description:Text("Connect to your Aurral server, then refresh to load discoveries."))}
            }.padding(24).frame(maxWidth:1100,alignment:.leading).frame(maxWidth:.infinity)
        }.background(DiscoverPalette.paper).foregroundStyle(DiscoverPalette.ink).navigationTitle("Discover")
        .refreshable{await model.refresh(force:true);model.markSeen()}
        .onAppear{visible=true;if scenePhase == .active{model.markSeen()}}
        .onDisappear{visible=false}
        .task{await model.refresh();if visible && scenePhase == .active{model.markSeen()}}
        .onChange(of:model.snapshot?.savedAt){_,_ in if visible && scenePhase == .active{model.markSeen()}}
        .onChange(of:scenePhase){_,phase in if visible && phase == .active{model.markSeen()}}
    }
    private func heading(_ title:String)->some View{Text(title).font(.system(.title2,design:.rounded).weight(.semibold))}
    @ViewBuilder private func releases(_ items:[DiscoverRelease],title:String)->some View{
        if !items.isEmpty{VStack(alignment:.leading,spacing:13){heading(title);ScrollView(.horizontal,showsIndicators:false){HStack(alignment:.top,spacing:18){ForEach(items){release in NavigationLink{DiscoverReleaseView(model:model,release:release,pauseMain:pauseMain,playFromLibrary:playFromLibrary)}label:{VStack(alignment:.leading,spacing:6){DiscoverArtwork(title:release.albumName,source:release.coverUrl,server:model.server);Text(release.albumName).font(.headline).lineLimit(2);Text(release.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1);Text(release.releaseDate ?? "Date TBA").font(.caption2.monospacedDigit()).foregroundStyle(.secondary);Text(release.albumType ?? "Release").font(.caption2.weight(.semibold))}}.buttonStyle(.plain).accessibilityIdentifier("discover.release."+release.id).frame(width:140)}}}}}
    }
    @ViewBuilder private func artists(_ items:[DiscoverArtist],title:String,subtitle:String)->some View{
        if !items.isEmpty{VStack(alignment:.leading,spacing:13){heading(title);Text(subtitle).font(.caption).foregroundStyle(.secondary);ScrollView(.horizontal,showsIndicators:false){HStack(alignment:.top,spacing:18){ForEach(items){artist in NavigationLink{DiscoverTracksView(model:model,title:artist.name,artist:artist.name,webURL:model.server.map{DiscoveryLinks.artist(artist,server:$0)},pauseMain:pauseMain,playFromLibrary:playFromLibrary,loader:{try await model.tracks(artist:artist)})}label:{VStack(alignment:.leading,spacing:7){DiscoverArtwork(title:artist.name,source:artist.image,server:model.server,circular:true);Text(artist.name).font(.headline).lineLimit(1);Text(title=="For you" ? artist.reason : artist.popularityLabel ?? "Trending").font(.caption).foregroundStyle(.secondary).lineLimit(3)}}.buttonStyle(.plain).accessibilityIdentifier("discover.artist."+artist.id).frame(width:140)}}}}}
    }
}
struct DiscoverReleaseView:View {
    @ObservedObject var model:DiscoveryModel
    let release:DiscoverRelease
    var pauseMain:()->Void
    var playFromLibrary:(DiscoverTrack,String)async throws->Bool
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:22){DiscoverArtwork(title:release.albumName,source:release.coverUrl,server:model.server,size:235);Text(release.albumName).font(.system(size:34,weight:.medium,design:.serif));Text(release.artistName).font(.title3);Label((release.upcoming() ? "Expected " : "Released ")+(release.releaseDate ?? "date to be announced"),systemImage:"calendar").font(.subheadline)
            Text(release.upcoming() ? "Coming soon. Availability can change before release day." : "A new release to explore. Full playback depends on its availability in your library.").foregroundStyle(.secondary)
            if let server=model.server,let url=DiscoveryLinks.release(release,server:server){Link(destination:url){Label("Open release in Aurral",systemImage:"arrow.up.right.square")}.buttonStyle(.borderedProminent)}
            if let id=release.artistMbid{NavigationLink("Explore the artist’s popular songs"){let artist=DiscoverArtist(mbid:id,name:release.artistName);DiscoverTracksView(model:model,title:artist.name,artist:artist.name,webURL:model.server.map{DiscoveryLinks.artist(artist,server:$0)},pauseMain:pauseMain,playFromLibrary:playFromLibrary,loader:{try await model.tracks(artist:artist)})}}
        }.padding(24).frame(maxWidth:700,alignment:.leading).frame(maxWidth:.infinity)}.background(DiscoverPalette.paper).navigationTitle("Release")
    }
}
struct DiscoverTracksView:View {
    @ObservedObject var model:DiscoveryModel
    let title:String
    let artist:String
    var webURL:URL?
    var pauseMain:()->Void
    var playFromLibrary:(DiscoverTrack,String)async throws->Bool
    var loader:()async throws->[DiscoverTrack]
    @State private var tracks:[DiscoverTrack]=[]
    @State private var loading=true
    @State private var error:String?
    @State private var finding=false
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:23){Text(title).font(.system(size:36,weight:.medium,design:.serif));Text(artist.isEmpty ? "Editorial song picks" : "Popular songs to explore").font(.headline);Text("Preview · up to 30 seconds. Play from library checks for the full song you already have.").font(.caption).foregroundStyle(.secondary)
            if loading{ProgressView()};if let error{Text(error).font(.callout).foregroundStyle(.secondary)}
            ForEach(tracks){track in DiscoverTrackRow(preview:model.preview,track:track,artist:artist,url:model.previewURL(track),server:model.server,pauseMain:pauseMain,finding:finding){Task{finding=true;defer{finding=false};do{let played=try await playFromLibrary(track,artist);if !played{error="This full song isn’t in your library yet. Open it in Aurral to check availability."}}catch{self.error="The library couldn’t be reached. Check your server connection and try again."}}}}
            if !loading && tracks.isEmpty{ContentUnavailableView("No previews available",systemImage:"music.note",description:Text("You can still explore this item in Aurral."))}
            if let webURL{Link(destination:webURL){Label("Open in Aurral",systemImage:"arrow.up.right.square")}.buttonStyle(.borderedProminent)}
        }.padding(24).frame(maxWidth:850,alignment:.leading).frame(maxWidth:.infinity)}.background(DiscoverPalette.paper).navigationTitle(title)
        .task{do{let loaded=try await loader();var seen=Set<String>();tracks=loaded.filter{seen.insert($0.id).inserted}}catch is CancellationError{}catch{self.error="Popular songs couldn’t load. You can retry by reopening this page."};loading=false}
        .onDisappear{model.preview.stop()}
    }
}
private struct DiscoverTrackRow:View {
    @ObservedObject var preview:DiscoveryPreview
    let track:DiscoverTrack
    let artist:String
    let url:URL?
    let server:URL?
    let pauseMain:()->Void
    var finding=false
    let play:()->Void
    var body:some View{VStack(alignment:.leading,spacing:10){HStack(spacing:12){DiscoverArtwork(title:track.title,source:track.artworkUrl,server:server,size:52);VStack(alignment:.leading,spacing:4){Text(track.title).font(.headline);Text(track.artistName ?? artist).font(.caption).foregroundStyle(.secondary)};Spacer()}
        HStack{Button{preview.toggle(id:track.id,url:url,beforePlay:pauseMain)}label:{Label(preview.currentID==track.id ? "Stop preview" : "Preview",systemImage:preview.currentID==track.id ? "stop.fill" : "play.fill")}.disabled(url==nil).accessibilityLabel((preview.currentID==track.id ? "Stop preview for " : "Preview ")+track.title);Spacer();Button(action:play){Label("Play from library",systemImage:"music.note.house")}.disabled(finding).accessibilityLabel("Play \(track.title) from library")}.font(.caption)
        if preview.currentID==track.id{Text("Preview · up to 30 seconds").font(.caption2).foregroundStyle(.secondary)}
        if let error=preview.error{Text(error).font(.caption2).foregroundStyle(.secondary)}
    }.padding(15).background(.white.opacity(0.75),in:RoundedRectangle(cornerRadius:18))}
}
#endif
