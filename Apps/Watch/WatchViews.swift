import SwiftUI
import WatchKit
import CadenceCore

struct WatchRoot:View {
    @Environment(\.isLuminanceReduced) private var dimmed
    @EnvironmentObject var store:WatchStore
    @State private var tab=0
    @State private var choosingSource=false
    @AppStorage("playbackSource") private var source="watch"
    private var deviceName:String{source=="phone" ? "iPhone" : source=="mac" ? "Mac" : "This Watch"}
    private var deviceIcon:String{source=="phone" ? "iphone" : source=="mac" ? "laptopcomputer" : "applewatch"}
    var body:some View {
        Group{
        if dimmed{NavigationStack{WatchAmbientPlayer(audio:store.audio,bridge:store.bridge,source:source)}.navigationBarTitleDisplayMode(.inline)}
        else{NavigationStack{
            Group{
                if source=="phone" || source=="mac"{
                    PhoneRemoteView(bridge:store.bridge,target:source,useOffline:{source="watch";tab=0},controlsActive:!choosingSource).id(source)
                }else{
                    TabView(selection:$tab){
                        WatchMixView(local:store.local,audio:store.audio,onPlay:{song in store.play(song);tab=1}).tag(0)
                        WatchPlayer(audio:store.audio,local:store.local,showLibrary:{tab=0},crownActive:tab==1 && !choosingSource).tag(1)
                        WatchSettings(local:store.local,bridge:store.bridge).tag(2)
                    }.tabViewStyle(.page(indexDisplayMode:.automatic))
                }
            }.navigationBarTitleDisplayMode(.inline).toolbar{
                ToolbarItem(placement:.topBarLeading){
                    Button{choosingSource=true}label:{HStack(spacing:4){Image(systemName:deviceIcon);Text(source=="watch" ? "Watch" : deviceName);Image(systemName:"chevron.down").font(.caption2)}.font(.caption2.weight(.semibold))}.buttonStyle(.plain).foregroundStyle(watchLime).accessibilityLabel("Playback device: "+deviceName).accessibilityHint("Choose Watch, iPhone or Mac").accessibilityIdentifier("watch.device")
                }
            }
        }}
        }.sheet(isPresented:$choosingSource){WatchSourcePicker(source:$source)}
            .onChange(of:dimmed){_,value in if value{choosingSource=false}else if source=="watch",store.audio.current != nil{tab=1}}
            .onChange(of:source){_,value in
                if value=="phone" || value=="mac"{store.audio.pause();store.bridge.requestPlayback(target:value)}
                else{tab=store.audio.current == nil ? 0 : 1}
            }
            .onAppear{
                if !["phone","mac","watch"].contains(source) || ProcessInfo.processInfo.arguments.contains("--demo"){source="watch"}
                if store.audio.current != nil{tab=1}
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--watch-ui-testing"),ProcessInfo.processInfo.arguments.contains("--remote-now-playing"){WatchDelegate().handleRemoteNowPlayingActivity()}
                #endif
            }
    }
}

struct WatchSourcePicker:View {
    @Environment(\.dismiss) private var dismiss
    @Binding var source:String
    var body:some View {
        NavigationStack{
            List{
                option("watch",name:"This Watch",detail:"Saved music · no phone needed",icon:"applewatch")
                option("phone",name:"iPhone",detail:"Control nearby iPhone playback",icon:"iphone")
                option("mac",name:"Mac",detail:"Control Mac through your iPhone",icon:"laptopcomputer")
            }.navigationTitle("Playback device")
        }
    }
    private func option(_ value:String,name:String,detail:String,icon:String)->some View {
        Button{source=value;dismiss()}label:{HStack(spacing:8){Image(systemName:icon).foregroundStyle(watchLime);VStack(alignment:.leading,spacing:3){Text(name);Text(detail).font(.caption2).foregroundStyle(.secondary)};Spacer(minLength:0);if source==value{Image(systemName:"checkmark").foregroundStyle(watchLime)}}.frame(minHeight:44).contentShape(Rectangle())}.accessibilityIdentifier("watch.device."+value).accessibilityValue(source==value ? "Selected" : "")
    }
}

struct WatchArtwork:View {
    var song:Song?;var data:Data?;var size:CGFloat=112
    var body:some View {
        ZStack{
            if let data,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}
            else{
                LinearGradient(colors:[Color(red:0.13,green:0.25,blue:0.21),Color(red:0.42,green:0.59,blue:0.35)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Circle().stroke(.white.opacity(0.15),lineWidth:size*0.12).padding(size*0.15)
                Image("CadenceMarkLime").resizable().scaledToFit().frame(width:size*0.7,height:size*0.7)
            }
        }.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:min(18,size/4))).accessibilityHidden(true)
    }
}

struct WatchMixView:View {
    @EnvironmentObject var store:WatchStore
    @ObservedObject var local:LocalLibrary
    @ObservedObject var audio:AudioController
    var onPlay:(Song?)->Void
    var body:some View {
        ScrollView{
            VStack(alignment:.leading,spacing:12){
                if let mix=local.mix{
                    Text(mix.name).font(.headline).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    Button{onPlay(nil)}label:{Label(playTitle,systemImage:"play.fill").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.tint(watchLime).foregroundStyle(.black).buttonStyle(.borderedProminent).disabled(local.readySongs.isEmpty).accessibilityIdentifier("watch.play")
                    readiness(mix)
                    NavigationLink{WatchSavedMixesView(local:local)}label:{Label("Saved playlists · \(local.mixes.count)",systemImage:"music.note.list")}.accessibilityIdentifier("watch.library")
                    if local.readyIDs.count<mix.songs.count{
                        Text("Only saved tracks play offline. Keep your iPhone nearby to finish syncing.").font(.caption2).foregroundStyle(.secondary)
                        Button("Check sync"){store.bridge.requestMix();local.acknowledge()}.accessibilityIdentifier("watch.sync")
                    }
                    ForEach(mix.songs){song in
                        Button{onPlay(song)}label:{HStack(spacing:8){VStack(alignment:.leading,spacing:4){Text(song.title).font(.body).lineLimit(2);Text(song.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)};Spacer(minLength:2);Image(systemName:local.readyIDs.contains(song.id) ? "play.circle.fill" : "arrow.down.circle").foregroundStyle(local.readyIDs.contains(song.id) ? watchLime : .gray)}.frame(minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).disabled(!local.readyIDs.contains(song.id)).accessibilityHint(local.readyIDs.contains(song.id) ? "Saved on this Watch" : "Waiting for transfer from iPhone")
                    }
                }else{
                    Image(systemName:"figure.run").font(.system(size:38,weight:.light)).foregroundStyle(watchLime)
                    Text("Your next\nfew miles.").font(.title2.bold())
                    Text("Send a playlist from Cadence on your iPhone. Once saved, leave your phone behind.").font(.footnote).foregroundStyle(.secondary)
                    Button("Explore demo"){store.enterDemo()}.accessibilityIdentifier("watch.demo")
                }
                if let message=local.message{Label(message,systemImage:"exclamationmark.circle").font(.caption2).foregroundStyle(.orange)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,8).padding(.bottom,16)
        }.navigationBarTitleDisplayMode(.inline)
    }
    private var playTitle:String {
        if audio.current != nil{return audio.isPlaying ? "Continue listening" : "Resume"}
        return local.mix.map{local.readyIDs.count<$0.songs.count}==true ? "Play saved tracks" : "Play playlist"
    }
    private func readiness(_ mix:RunMix)->some View {
        let complete=local.readyIDs.count==mix.songs.count
        let seconds=local.readySongs.reduce(0){$0+max(0,min(604800,$1.duration ?? 0))}
        return VStack(alignment:.leading,spacing:5){
            Label(complete ? "Ready for your run" : "\(local.readyIDs.count) of \(mix.songs.count) tracks saved",systemImage:complete ? "checkmark.circle.fill" : "arrow.down.circle").font(.caption).foregroundStyle(complete ? watchLime : .secondary)
            if !complete{ProgressView(value:Double(local.readyIDs.count),total:Double(max(1,mix.songs.count))).tint(watchLime).accessibilityLabel("Playlist download progress")}
            if seconds>0{Text("\(Int(ceil(Double(seconds)/60))) min saved offline").font(.caption2).foregroundStyle(.secondary)}
        }
    }
}

struct WatchSavedMixesView:View {
    @EnvironmentObject var store:WatchStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var local:LocalLibrary
    @State private var removal:RunMix?
    var body:some View {
        List{
            ForEach(local.mixes,id:\.id){mix in
                let ready=local.ready(mix).count
                Button{store.selectMix(mix.id);dismiss()}label:{HStack{VStack(alignment:.leading,spacing:4){Text(mix.name).lineLimit(2);Text("\(ready) / \(mix.songs.count) saved").font(.caption2).foregroundStyle(.secondary)};Spacer(minLength:0);Image(systemName:local.mix?.id==mix.id ? "checkmark.circle.fill" : ready==mix.songs.count ? "arrow.down.circle.fill" : "clock").foregroundStyle(local.mix?.id==mix.id ? watchLime : .secondary)}}.accessibilityIdentifier("watch.mix."+mix.id).accessibilityValue((local.mix?.id==mix.id ? "Selected. " : "")+"\(ready) of \(mix.songs.count) tracks saved").accessibilityAction(named:Text("Remove saved playlist")){removal=mix}
                    .swipeActions(edge:.trailing,allowsFullSwipe:false){Button("Remove",role:.destructive){removal=mix}}
            }
            if local.mixes.isEmpty{Text("Send a playlist from iPhone.").font(.footnote).foregroundStyle(.secondary)}
        }.navigationTitle("Saved playlists").confirmationDialog("Remove this saved playlist?",isPresented:Binding(get:{removal != nil},set:{if !$0{removal=nil}})){Button("Remove playlist",role:.destructive){if let removal{store.removeMix(removal)};removal=nil}}message:{Text("Shared audio stays saved when another playlist needs it.")}
    }
}

struct WatchPlayer:View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ObservedObject var audio:AudioController
    @ObservedObject var local:LocalLibrary
    var showLibrary:()->Void
    var crownActive:Bool
    private enum Sheet:String,Identifiable{case queue,seek;var id:String{rawValue}}
    @State private var presented:Sheet?
    var body:some View {
        ScrollView{
            VStack(spacing:6){
                if let song=audio.current{
                    HStack(spacing:4){
                        WatchTrackHeading(song:song,showsArtwork:false)
                        if crownActive && scenePhase == .active && presented==nil{
                            WatchVolume(active:!voiceOver).frame(width:50,height:50).accessibilityLabel("Watch volume").accessibilityHint("Turn the Digital Crown to adjust headphone volume").accessibilityIdentifier("watch.volume")
                        }else{Image(systemName:"speaker.wave.2.fill").frame(width:50,height:50).accessibilityHidden(true)}
                    }
                    WatchTransport(isPlaying:audio.isPlaying,device:"Watch",previous:{audio.previous()},toggle:{audio.toggle()},next:{audio.next()})
                    Button{presented = .seek}label:{VStack(spacing:3){ProgressView(value:min(max(0,audio.elapsed),max(audio.duration,1)),total:max(audio.duration,1)).tint(watchLime);HStack{Text(watchTime(audio.elapsed));Spacer();Text(watchTime(audio.duration))}.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)}.frame(minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).disabled(audio.duration<=0).accessibilityLabel("Seek in track").accessibilityValue(watchTime(audio.elapsed)+" of "+watchTime(audio.duration)).accessibilityIdentifier("watch.seek")
                    HStack(spacing:0){
                        Button{audio.shuffle()}label:{Image(systemName:"shuffle").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle()).foregroundStyle(audio.isShuffled ? watchLime : .secondary)}.accessibilityLabel("Shuffle").accessibilityValue(audio.isShuffled ? "On" : "Off")
                        Button{presented = .queue}label:{Image(systemName:"list.bullet").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.accessibilityLabel("Open queue").accessibilityIdentifier("watch.queue")
                        Button{audio.cycleRepeat()}label:{Image(systemName:audio.repeatMode == .one ? "repeat.1" : "repeat").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle()).foregroundStyle(audio.repeats ? watchLime : .secondary)}.accessibilityLabel(audio.repeatMode.label)
                    }.buttonStyle(.plain)
                    if let error=audio.error{Text(error).font(.caption2).foregroundStyle(.orange);Button("Retry playback"){audio.retryCurrent()}}
                }else{
                    Image(systemName:"headphones").font(.largeTitle).foregroundStyle(watchLime)
                    Text("Ready when you are.").font(.title3.bold())
                    Text("Start a saved track from your library.").font(.footnote).foregroundStyle(.secondary)
                    Button("Open saved music",action:showLibrary)
                }
            }.padding(.horizontal,6).padding(.top,4).padding(.bottom,12)
        }.sheet(item:$presented){sheet in
            switch sheet{
            case .queue:WatchQueueView(audio:audio)
            case .seek:if let song=audio.current{WatchSeekView(song:song,elapsed:audio.elapsed,duration:audio.duration,commit:{if audio.current?.id==song.id{audio.seek($0)}})}
            }
        }.onChange(of:audio.current?.id){_,_ in if presented == .seek{presented=nil}}
    }
}

struct WatchSettings:View {
    @EnvironmentObject var store:WatchStore
    @ObservedObject var local:LocalLibrary
    @ObservedObject var bridge:WatchBridge
    @State private var erase=false
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:14){
            Text("RUN LIGHT").font(.caption2.bold()).tracking(2).foregroundStyle(watchLime)
            Label("\(local.mixes.count) of 10 playlists saved",systemImage:"music.note.list").font(.footnote)
            Label("Connect headphones directly to this Watch for offline listening.",systemImage:"headphones").font(.footnote).foregroundStyle(.secondary)
            Text("Saved tracks need no phone or internet. New tracks arrive from your paired iPhone when watchOS schedules the transfer.").font(.footnote).foregroundStyle(.secondary)
            Text(bridge.status).font(.caption2).foregroundStyle(.secondary)
            Button("Check for music"){bridge.requestMix();local.acknowledge()}
            Button("Erase saved music",role:.destructive){erase=true}.disabled(local.mixes.isEmpty)
            Text("Cadence · \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1")").font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical,12)}
            .confirmationDialog("Erase saved music?",isPresented:$erase,titleVisibility:.visible){Button("Erase music",role:.destructive){store.clear()}}message:{Text("Music is removed from this Watch. Send a fresh playlist from your iPhone to listen again.")}
    }
}
