import SwiftUI
import CadenceCore

struct PhoneRemoteView:View {
    @ObservedObject var bridge:WatchBridge
    var target="phone"
    private var name:String{target=="mac" ? "Mac" : "iPhone"}
    private var state:PhonePlayback?{target=="mac" ? bridge.macRemote.playback : bridge.phonePlayback}
    private var connected:Bool{bridge.phoneReachable && (target != "mac" || (bridge.macRemote.connected && Date().timeIntervalSince(bridge.macRemote.checkedAt)<10))}
    private func control(_ action:PhoneCommand.Action,value:Double?=nil){bridge.control(action,value:value,target:target)}
    @State private var seekValue=0.0
    @State private var seeking=false
    @State private var volumeValue=1.0
    @State private var changingVolume=false
    private let lime=Color(red:215/255,green:245/255,blue:103/255)
    var body:some View {
        ScrollView{
            VStack(spacing:10){
                Label(connected ? (state?.song == nil ? name+" connected" : "Playing on \(name)") : name+" disconnected",systemImage:target=="mac" ? "laptopcomputer" : "iphone").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
                if let state,let song=state.song{
                    HStack(spacing:8){
                        WatchArtwork(song:song,data:state.artwork,size:42)
                        VStack(alignment:.leading,spacing:3){Text(song.title).font(.system(size:14,weight:.semibold)).lineLimit(2);Text(song.subtitle).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)}
                        Spacer(minLength:0)
                    }
                    HStack{
                        remote("Previous track",icon:"backward.end.fill"){control(.previous)}
                        Button{control(state.isPlaying ? .pause : .play)}label:{Image(systemName:state.isPlaying ? "pause.fill" : "play.fill").font(.system(size:23)).frame(width:62,height:48).background(lime,in:Capsule()).foregroundStyle(.black)}.buttonStyle(.plain).accessibilityLabel(state.isPlaying ? "Pause \(name)" : "Play \(name)")
                        remote("Next track",icon:"forward.end.fill"){control(.next)}
                    }.disabled(!connected)
                    Slider(value:Binding(get:{seeking ? seekValue : min(state.elapsed,max(1,state.duration))},set:{seekValue=$0}),in:0...max(1,state.duration),onEditingChanged:{editing in seeking=editing;if !editing{control(.seek,value:seekValue)}}).tint(lime).disabled(!connected).accessibilityLabel("\(name) playback position")
                    Text(time(seeking ? seekValue : state.elapsed)+" / "+time(state.duration)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                    HStack{
                        remote("Shuffle \(name)",icon:"shuffle",active:state.shuffled){control(.shuffle,value:state.shuffled ? 0 : 1)}
                        Spacer()
                        remote("Repeat \(name)",icon:"repeat",active:state.repeats){control(.repeatMode,value:state.repeats ? 0 : 1)}
                    }.disabled(!connected)
                    Label("Cadence volume",systemImage:"speaker.wave.2").font(.caption2).foregroundStyle(.secondary)
                    Slider(value:Binding(get:{changingVolume ? volumeValue : state.volume},set:{volumeValue=$0}),in:0...1,onEditingChanged:{editing in changingVolume=editing;if !editing{control(.volume,value:volumeValue)}}).tint(lime).disabled(!connected).accessibilityLabel("\(name) Cadence volume")
                }else{
                    Image("CadenceMarkLime").resizable().scaledToFit().frame(width:44,height:44).padding(.top,8)
                    Text("Your \(name).\nYour soundtrack.").font(.system(size:20,weight:.semibold,design:.rounded)).multilineTextAlignment(.center)
                    Text("Start a song in Cadence on your \(name). Control it here, or choose Watch for your saved offline mix.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !connected{Text(target=="mac" ? (bridge.macRemote.message ?? "Connect Mac playback in Cadence on iPhone. Keep Tailscale connected on both and your iPhone nearby.") : "Keep your iPhone nearby with Bluetooth enabled. Open Cadence there to reconnect. Watch playback works independently with a saved mix.").font(.caption2).foregroundStyle(.secondary)}
                if let error=bridge.remoteError{Text(error).font(.caption2).foregroundStyle(.orange)}
                Button("Reconnect to \(name)"){bridge.requestPlayback(target:target)}.font(.caption2)
            }.padding(.horizontal,8).padding(.top,8).padding(.bottom,18)
        }.task{while !Task.isCancelled{bridge.refresh();bridge.requestPlayback(target:target);try? await Task.sleep(for:.seconds(2))}}
    }
    private func remote(_ title:String,icon:String,active:Bool=false,action:@escaping()->Void)->some View{Button(action:action){Image(systemName:icon).frame(width:42,height:40).foregroundStyle(active ? lime : .white)}.buttonStyle(.plain).accessibilityLabel(title)}
    private func time(_ value:Double)->String{let seconds=Int(value.isFinite ? max(0,value) : 0);return String(format:"%d:%02d",seconds/60,seconds%60)}
}
