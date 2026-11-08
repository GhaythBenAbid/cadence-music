#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

struct QueueView:View {
    @ObservedObject var audio:AudioController
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                Section("Playback"){
                    Picker("Repeat",selection:$audio.repeatMode){ForEach(RepeatMode.allCases,id:\.self){Text($0.label).tag($0)}}
                    Toggle("Autoplay library recommendations",isOn:$audio.autoplay).disabled(audio.relatedSongs==nil)
                    if audio.preparingRelated{ProgressView("Finding more music…")}
                    if let error=audio.error{Text(error).font(.caption);HStack{Button("Retry current song"){audio.retryCurrent()};Button("Skip song"){audio.next()}}}
                }

                if let song=audio.current {Section("Now playing"){Text(song.title).font(.headline);Text(song.subtitle).foregroundStyle(.secondary)}}
                Section("Up next · \(audio.upcoming.count)") {
                    ForEach(Array(audio.upcoming.enumerated()),id:\.element.id){index,entry in
                        HStack {
                            Button{audio.playEntry(entry.id)}label:{VStack(alignment:.leading){Text(entry.song.title);Text(entry.song.subtitle).font(.caption).foregroundStyle(.secondary)}}.buttonStyle(.plain)
                            Spacer()
                            Button{audio.moveUpcoming(from:index,to:index-1)}label:{Image(systemName:"arrow.up")}.disabled(index==0).accessibilityLabel("Move \(entry.song.title) up")
                            Button{audio.moveUpcoming(from:index,to:index+1)}label:{Image(systemName:"arrow.down")}.disabled(index==audio.upcoming.count-1).accessibilityLabel("Move \(entry.song.title) down")
                            Button(role:.destructive){audio.removeUpcoming(entry.id)}label:{Image(systemName:"minus.circle")}.accessibilityLabel("Remove \(entry.song.title) from queue")
                        }.buttonStyle(.borderless)
                    }
                    if audio.upcoming.isEmpty{Text("Choose Play next or Add to queue from a song’s menu.").foregroundStyle(.secondary)}
                }
            }.navigationTitle("Queue").toolbar {
                ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}
                ToolbarItem(placement:.cancellationAction){Button("Clear upcoming",role:.destructive){audio.clearUpcoming()}.disabled(audio.upcoming.isEmpty)}
            }
        }
        #if os(macOS)
        .frame(minWidth:560,minHeight:450)
        #endif
    }
}

struct PlaylistEditor:View {
    var original:Playlist?
    var initialSongs:[Song]=[]
    var load:(String)async throws->Playlist
    var search:(String)async throws->[Song]
    var save:(String,[Song],Playlist?)async throws->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var songs:[Song]=[]
    @State private var baseline:Playlist?
    @State private var query=""
    @State private var results:[Song]=[]
    @State private var busy=false
    @State private var loading=true
    @State private var error:String?
    var body:some View {
        NavigationStack {
            List {
                Section {TextField("Playlist name",text:$name).accessibilityIdentifier("playlist.name")}
                if let error{Section{Text(error).foregroundStyle(.red)}}
                if loading{ProgressView()}
                Section("Tracks · \(songs.count)") {
                    ForEach(Array(songs.enumerated()),id:\.offset){index,song in
                        HStack{VStack(alignment:.leading){Text(song.title);Text(song.subtitle).font(.caption).foregroundStyle(.secondary)};Spacer()
                            Button{songs.swapAt(index,index-1)}label:{Image(systemName:"arrow.up")}.disabled(index==0).accessibilityLabel("Move \(song.title) up")
                            Button{songs.swapAt(index,index+1)}label:{Image(systemName:"arrow.down")}.disabled(index==songs.count-1).accessibilityLabel("Move \(song.title) down")
                            Button(role:.destructive){songs.remove(at:index)}label:{Image(systemName:"minus.circle")}.accessibilityLabel("Remove \(song.title) from playlist")
                        }.buttonStyle(.borderless)
                    }
                }
                Section("Add from your library") {
                    TextField("Find a song",text:$query).accessibilityIdentifier("playlist.search")
                    ForEach(results){song in Button{songs.append(song)}label:{Label(song.title,systemImage:"plus.circle")}.accessibilityLabel("Add \(song.title) to playlist")}
                }
            }.disabled(busy || loading).navigationTitle(original==nil ? "New playlist" : "Edit playlist")
            .toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(busy)}
                ToolbarItem(placement:.confirmationAction){Button(busy ? "Saving…" : "Save"){Task{busy=true;defer{busy=false};do{try await save(name,songs,baseline);dismiss()}catch{self.error=error.localizedDescription}}}.disabled(busy || loading || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("playlist.save")}
            }
            .task{do{if let original{let full=try await load(original.id);baseline=full;name=full.name;songs=full.entry ?? []}else{songs=initialSongs}}catch{self.error=error.localizedDescription;return};loading=false}
            .task(id:query){guard !query.trimmingCharacters(in:.whitespaces).isEmpty else{results=[];return};do{try await Task.sleep(for:.milliseconds(300));let found=try await search(query);try Task.checkCancellation();results=found}catch is CancellationError{}catch{self.error=error.localizedDescription}}
        }
        #if os(macOS)
        .frame(minWidth:600,minHeight:550)
        #endif
        .interactiveDismissDisabled(busy)
    }
}

struct PlaylistPicker:View {
    let song:Song
    let playlists:[Playlist]
    let add:(Song,Playlist)async throws->Void
    let create:(String,[Song],Playlist?)async throws->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var busy=false
    @State private var error:String?
    var body:some View {
        NavigationStack{List{
            if let error{Text(error).foregroundStyle(.red)}
            Section("New playlist"){TextField("Playlist name",text:$name);Button("Create and add song"){perform{try await create(name,[song],nil)}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            Section("Your playlists"){ForEach(playlists.filter{!$0.id.hasPrefix("flow:")}){playlist in Button(playlist.name){perform{try await add(song,playlist)}}}}
            }.disabled(busy).navigationTitle("Add to playlist").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(busy)}}
        }
        #if os(macOS)
        .frame(minWidth:420,minHeight:400)
        #endif
    }
    private func perform(_ work:@escaping()async throws->Void){Task{busy=true;defer{busy=false};do{try await work();dismiss()}catch{self.error=error.localizedDescription}}}
}
#endif
