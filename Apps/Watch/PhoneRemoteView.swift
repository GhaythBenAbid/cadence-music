import SwiftUI
import CadenceCore

struct PhoneRemoteView:View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var bridge:WatchBridge
    var target="phone"
    var useOffline:()->Void
    var controlsActive=true
    @State private var seeking=false
    private var name:String{target=="mac" ? "Mac" : "iPhone"}
    private var state:PhonePlayback?{target=="mac" ? bridge.macRemote.playback : bridge.phonePlayback}
    private var connected:Bool{
        guard bridge.phoneReachable else{return false}
        if target=="mac"{return bridge.macRemote.connected && Date().timeIntervalSince(bridge.macRemote.checkedAt)<10}
        return state.map{Date().timeIntervalSince($0.updatedAt)<10} ?? false
    }
    private var status:String{
        guard connected else{return name+" unavailable"}
        guard state?.song != nil else{return name+" connected"}
        return (state?.isPlaying==true ? "Playing on " : "Paused on ")+name
    }
    private func control(_ action:PhoneCommand.Action,value:Double?=nil){bridge.control(action,value:value,target:target)}
    var body:some View {
        ScrollView{
            VStack(spacing:6){
                if let state,let song=state.song{
                    HStack(spacing:4){WatchTrackHeading(song:song,showsArtwork:false);WatchRemoteVolume(value:state.volume,enabled:connected,active:controlsActive && !seeking,device:name,send:{control(.volume,value:$0)})}
                    WatchTransport(isPlaying:state.isPlaying,device:name,previous:{control(.previous)},toggle:{control(state.isPlaying ? .pause : .play)},next:{control(.next)}).disabled(!connected)
                    Button{seeking=true}label:{VStack(spacing:3){ProgressView(value:max(0,min(state.elapsed,max(1,state.duration))),total:max(1,state.duration)).tint(watchLime);HStack{Text(watchTime(state.elapsed));Spacer();Text(watchTime(state.duration))}.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)}.frame(minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).disabled(!connected || state.duration<=0).accessibilityLabel("Seek on "+name).accessibilityIdentifier("watch.remote.seek")
                    Text(status).font(.caption2).foregroundStyle(connected ? Color.secondary : Color.orange)
                    HStack{
                        Button{control(.shuffle,value:state.shuffled ? 0 : 1)}label:{Image(systemName:"shuffle").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle()).foregroundStyle(state.shuffled ? watchLime : .secondary)}.accessibilityLabel("Shuffle "+name).accessibilityValue(state.shuffled ? "On" : "Off")
                        Button{control(.repeatMode,value:state.repeats ? 0 : 1)}label:{Image(systemName:"repeat").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle()).foregroundStyle(state.repeats ? watchLime : .secondary)}.accessibilityLabel("Repeat "+name).accessibilityValue(state.repeats ? "On" : "Off")
                    }.buttonStyle(.plain).disabled(!connected)
                }else{
                    Image("CadenceMarkLime").resizable().scaledToFit().frame(width:38,height:38)
                    Text(connected ? "Ready on "+name : "Connect your "+name).font(.title3.bold()).multilineTextAlignment(.center)
                    Text("Start a song in Cadence on your \(name), then control it here.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !connected{
                    Text(target=="mac" ? (bridge.macRemote.message ?? "Connect Mac playback in Cadence on iPhone. Keep Tailscale connected on both devices and the iPhone app open.") : "Keep your paired iPhone nearby with Bluetooth enabled. Open Cadence there to reconnect.").font(.caption2).foregroundStyle(.secondary)
                    Button("Open saved Watch music",action:useOffline).accessibilityIdentifier("watch.remote.offline")
                }
                if let error=bridge.remoteError{Label(error,systemImage:"exclamationmark.circle").font(.caption2).foregroundStyle(.orange)}
                Button("Reconnect to "+name){bridge.requestPlayback(target:target)}.font(.footnote).accessibilityIdentifier("watch.remote.reconnect")
            }.padding(.horizontal,6).padding(.top,4).padding(.bottom,14)
        }.sheet(isPresented:$seeking){if let state,let song=state.song{WatchSeekView(song:song,elapsed:state.elapsed,duration:state.duration,commit:{if connected,self.state?.song?.id==song.id{control(.seek,value:$0)}})}}
            .onChange(of:state?.song?.id){_,_ in seeking=false}
            .task(id:scenePhase){
                guard scenePhase == .active else{return}
                while !Task.isCancelled{
                    bridge.refresh();bridge.requestPlayback(target:target)
                    do{try await Task.sleep(for:.seconds(2))}catch{return}
                }
            }
    }
}
