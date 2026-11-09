import SwiftUI
import CadenceCore

let watchLime=Color(red:0.84,green:0.96,blue:0.4)

func watchTime(_ value:Double)->String {
    let seconds=Int(value.isFinite ? max(0,min(value,604800)) : 0)
    return String(format:"%d:%02d",seconds/60,seconds%60)
}

struct WatchTrackHeading:View {
    let song:Song
    var artwork:Data?
    var showsArtwork=true
    var body:some View {
        HStack(spacing:8){
            if showsArtwork{WatchArtwork(song:song,data:artwork,size:38)}
            VStack(alignment:.leading,spacing:2){
                Text(song.title).font(.headline).lineLimit(2)
                Text(song.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.accessibilityElement(children:.combine).accessibilityIdentifier("watch.track")
    }
}

struct WatchTransport:View {
    var isPlaying:Bool
    var device:String
    var previous:()->Void
    var toggle:()->Void
    var next:()->Void
    var body:some View {
        HStack(spacing:0){
            Button(action:previous){Image(systemName:"backward.end.fill").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.accessibilityLabel("Previous track")
            Button(action:toggle){Image(systemName:isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width:52,height:44).background(watchLime,in:Capsule()).foregroundStyle(.black)}.accessibilityLabel((isPlaying ? "Pause " : "Play ")+device).accessibilityIdentifier("watch.transport.play")
            Button(action:next){Image(systemName:"forward.end.fill").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.accessibilityLabel("Next track")
        }.buttonStyle(.plain)
    }
}

struct WatchSeekView:View {
    @Environment(\.dismiss) private var dismiss
    let song:Song
    let elapsed:Double
    let duration:Double
    var commit:(Double)->Void
    @State private var position=0.0
    private var total:Double{duration.isFinite ? max(0,duration) : 0}
    var body:some View {
        NavigationStack{
            ScrollView{
                VStack(spacing:12){
                    Text(song.title).font(.headline).lineLimit(2)
                    Text(watchTime(position)+" / "+watchTime(total)).font(.caption.monospacedDigit())
                    Slider(value:$position,in:0...max(1,total)).tint(watchLime).accessibilityLabel("Playback position").accessibilityIdentifier("watch.seek.slider")
                    Button("Seek to "+watchTime(position)){commit(position);dismiss()}.disabled(total<=0).accessibilityIdentifier("watch.seek.apply")
                }.padding(.vertical,8)
            }.navigationTitle("Track position")
        }.onAppear{position=min(max(0,elapsed.isFinite ? elapsed : 0),total)}
    }
}

struct WatchQueueView:View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var audio:AudioController
    @State private var clear=false
    var body:some View {
        NavigationStack{
            List{
                if let current=audio.current{
                    Section("Now playing"){
                        Label{VStack(alignment:.leading){Text(current.title);Text(current.subtitle).font(.caption2).foregroundStyle(.secondary)}}icon:{Image(systemName:audio.isPlaying ? "waveform" : "pause.fill").foregroundStyle(watchLime)}
                    }
                }
                Section("Up next · \(audio.upcoming.count)"){
                    ForEach(audio.upcoming){entry in
                        Button{audio.playEntry(entry.id);dismiss()}label:{VStack(alignment:.leading,spacing:3){Text(entry.song.title).lineLimit(2);Text(entry.song.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)}}
                            .accessibilityIdentifier("watch.queue."+entry.id).accessibilityHint("Play this upcoming song").accessibilityAction(named:Text("Remove from queue")){audio.removeUpcoming(entry.id)}
                            .swipeActions(edge:.trailing,allowsFullSwipe:false){Button("Remove",role:.destructive){audio.removeUpcoming(entry.id)}}
                    }
                    if audio.upcoming.isEmpty{Text(audio.repeatMode == .off ? "You're at the end of this queue." : audio.repeatMode.label).font(.footnote).foregroundStyle(.secondary)}
                }
                if !audio.upcoming.isEmpty{Button("Clear up next",role:.destructive){clear=true}}
            }.navigationTitle("Queue")
                .confirmationDialog("Clear upcoming songs?",isPresented:$clear,titleVisibility:.visible){Button("Clear up next",role:.destructive){audio.clearUpcoming()}}message:{Text("The current song keeps playing. Your saved playlist stays on this Watch.")}
        }
    }
}
