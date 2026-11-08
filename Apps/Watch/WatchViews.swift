import SwiftUI
import WatchKit
import CadenceCore

private let lime=Color(red:0.84,green:0.96,blue:0.4)
struct WatchRoot:View{
    @EnvironmentObject var store:WatchStore
    @State private var tab=0
    @AppStorage("playbackSource") private var source="phone"
    var body:some View{
        VStack(spacing:0){
            HStack(spacing:5){sourceButton("phone",label:"iPhone",icon:"iphone");sourceButton("mac",label:"Mac",icon:"laptopcomputer");sourceButton("watch",label:"Watch",icon:"applewatch")}.padding(.horizontal,5)
            if source=="phone" || source=="mac"{PhoneRemoteView(bridge:store.bridge,target:source).id(source)}
            else{TabView(selection:$tab){
                NavigationStack{WatchMixView(local:store.local,onPlay:{song in store.play(song);tab=1})}.tag(0)
                WatchPlayer(audio:store.audio,local:store.local).tag(1)
                WatchSettings(local:store.local,bridge:store.bridge).tag(2)
            }.tabViewStyle(.verticalPage)}
        }.onChange(of:source){_,value in if value=="phone" || value=="mac"{store.audio.pause();store.bridge.requestPlayback(target:value)}}
        .onAppear{if ProcessInfo.processInfo.arguments.contains("--demo"){source="watch"}}
    }
    private func sourceButton(_ value:String,label:String,icon:String)->some View{
        Button{source=value}label:{Label(label,systemImage:icon).font(.system(size:9,weight:.semibold)).frame(maxWidth:.infinity).frame(height:32).background(source==value ? lime : Color.white.opacity(0.1),in:Capsule()).foregroundStyle(source==value ? Color.black : .white)}.buttonStyle(.plain).accessibilityLabel("Play on \(label)")
    }
}
struct WatchArtwork:View{
    var song:Song?;var data:Data?;var size:CGFloat=112
    var body:some View{
        ZStack{
            if let data,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFill()}
            else{
                LinearGradient(colors:[Color(red:0.13,green:0.25,blue:0.21),Color(red:0.42,green:0.59,blue:0.35)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Circle().stroke(.white.opacity(0.15),lineWidth:size*0.12).padding(size*0.15)
                Image("CadenceMarkLime").resizable().scaledToFit().frame(width:size*0.7,height:size*0.7)
            }
        }.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:18)).accessibilityHidden(true)
    }
}
struct WatchMixView:View{
    @EnvironmentObject var store:WatchStore
    @ObservedObject var local:LocalLibrary
    var onPlay:(Song?)->Void
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:13){
                HStack(spacing:5){Image("CadenceMarkLime").resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true);Text("CADENCE").font(.system(size:10,weight:.bold,design:.rounded)).tracking(2)}.foregroundStyle(lime)
                NavigationLink("Saved playlists · \(local.mixes.count)"){WatchSavedMixesView(local:local)}
                if let mix=local.mix{
                    Text(mix.name).font(.system(size:25,weight:.semibold,design:.rounded)).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:5){Image(systemName:local.readyIDs.count==mix.songs.count ? "checkmark.circle.fill" : "arrow.down.circle");Text(local.readyIDs.count==mix.songs.count ? "Ready for your run" : "\(local.readyIDs.count) / \(mix.songs.count) saved")}.font(.caption2).foregroundStyle(lime)
                    Button{onPlay(nil)}label:{Label("Let's go",systemImage:"play.fill").font(.headline).frame(maxWidth:.infinity)}.tint(lime).foregroundStyle(.black).buttonStyle(.borderedProminent).disabled(local.readySongs.isEmpty).accessibilityIdentifier("watch.play")
                    ForEach(mix.songs){song in
                        Button{onPlay(song)}label:{HStack(spacing:8){VStack(alignment:.leading,spacing:4){Text(song.title).font(.system(size:14,weight:.medium)).lineLimit(2);Text(song.subtitle).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)};Spacer(minLength:2);Image(systemName:local.readyIDs.contains(song.id) ? "play.circle" : "clock").foregroundStyle(local.readyIDs.contains(song.id) ? lime : .gray)}}.buttonStyle(.plain).padding(.vertical,6).disabled(!local.readyIDs.contains(song.id))
                    }
                }else{
                    Image(systemName:"figure.run").font(.system(size:48,weight:.ultraLight)).foregroundStyle(lime).padding(.vertical,8)
                    Text("Your next\nfew miles.").font(.system(size:29,weight:.semibold,design:.rounded))
                    Text("Choose a mix in Cadence on your iPhone, then tap Send to Watch.").font(.footnote).foregroundStyle(.secondary)
                    Button("Explore demo"){store.enterDemo()}.font(.footnote).padding(.top,4).accessibilityIdentifier("watch.demo")
                }
                if let message=local.message{Text(message).font(.caption2).foregroundStyle(.orange)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,7).padding(.bottom,20)
        }.navigationBarTitleDisplayMode(.inline)
    }
}
struct WatchSavedMixesView:View {
    @EnvironmentObject var store:WatchStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var local:LocalLibrary
    @State private var removal:RunMix?
    var body:some View{List{
        ForEach(local.mixes,id:\.id){mix in VStack(alignment:.leading,spacing:7){
            Button{store.selectMix(mix.id);dismiss()}label:{VStack(alignment:.leading){Text(mix.name);Text("\(local.ready(mix).count) / \(mix.songs.count) saved").font(.caption2).foregroundStyle(.secondary)}}.accessibilityIdentifier("watch.mix."+mix.id)
            Button("Remove playlist",role:.destructive){removal=mix}.font(.caption2)
        }}
        if local.mixes.isEmpty{Text("Send a playlist from iPhone.")}
    }.navigationTitle("Saved playlists").confirmationDialog("Remove this saved playlist?",isPresented:Binding(get:{removal != nil},set:{if !$0{removal=nil}})){Button("Remove playlist",role:.destructive){if let removal{store.removeMix(removal)};removal=nil}}message:{Text("Shared audio stays saved when another playlist needs it.")}}
}
struct WatchPlayer:View{
    @ObservedObject var audio:AudioController
    @ObservedObject var local:LocalLibrary
    var body:some View{
        ScrollView{
            VStack(spacing:10){
                if let song=audio.current{
                    WatchArtwork(song:song,data:local.artwork(song),size:93)
                    Text(song.title).font(.system(size:16,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center)
                    Text(song.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    ProgressView(value:min(audio.elapsed,max(audio.duration,1)),total:max(audio.duration,1)).tint(lime)
                    HStack{Button{audio.previous()}label:{Image(systemName:"backward.end.fill").frame(width:38,height:38)}.buttonStyle(.plain).accessibilityLabel("Previous track");Spacer(minLength:4);Button{audio.toggle()}label:{Image(systemName:audio.isPlaying ? "pause.fill" : "play.fill").font(.system(size:22)).frame(width:56,height:48).background(lime,in:Capsule()).foregroundStyle(.black)}.buttonStyle(.plain).accessibilityLabel(audio.isPlaying ? "Pause" : "Play");Spacer(minLength:4);Button{audio.next()}label:{Image(systemName:"forward.end.fill").frame(width:38,height:38)}.buttonStyle(.plain).accessibilityLabel("Next track")}
                    HStack{Button{audio.shuffle()}label:{Image(systemName:"shuffle").foregroundStyle(audio.isShuffled ? lime : .secondary)}.buttonStyle(.plain).frame(width:44,height:35).accessibilityLabel("Shuffle");Text(time(audio.elapsed)+" / "+time(audio.duration)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary);Button{audio.cycleRepeat()}label:{Image(systemName:audio.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(audio.repeats ? lime : .secondary)}.buttonStyle(.plain).frame(width:44,height:35).accessibilityLabel(audio.repeatMode.label)}
                    WatchVolume().frame(height:35)
                    if let error=audio.error{Text(error).font(.caption2).foregroundStyle(.orange)}
                }else{Image(systemName:"headphones").font(.system(size:48,weight:.ultraLight)).foregroundStyle(lime);Text("Make room\nfor the music.").font(.system(size:25,weight:.semibold,design:.rounded)).multilineTextAlignment(.center);Text("Start a saved track from your mix.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)}
            }.padding(.horizontal,7).padding(.vertical,15)
        }
    }
    func time(_ seconds:Double)->String{let n=max(0,Int(seconds.isFinite ? seconds : 0));return String(format:"%d:%02d",n/60,n%60)}
}
struct WatchSettings:View{
    @EnvironmentObject var store:WatchStore
    @ObservedObject var local:LocalLibrary
    @ObservedObject var bridge:WatchBridge
    @State private var erase=false
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:17){Text("RUN LIGHT").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(lime);Text("All set? That's\nall you need.").font(.system(size:24,weight:.semibold,design:.rounded));Label("\(local.mixes.count) / 10 playlists saved",systemImage:"music.note.list").font(.footnote);Text("Saved tracks play without your iPhone or an internet connection. Connect your earbuds directly to this Watch.").font(.footnote).foregroundStyle(.secondary);Text(bridge.status).font(.caption2).foregroundStyle(.secondary);Button("Check for your mix"){bridge.requestMix();local.acknowledge()}.font(.footnote);Button("Erase saved music",role:.destructive){erase=true}.font(.footnote);Text("Cadence · \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1")").font(.caption2).foregroundStyle(.secondary)}.padding(.horizontal,7).padding(.vertical,12)}
        .confirmationDialog("Erase saved music?",isPresented:$erase,titleVisibility:.visible){Button("Erase music",role:.destructive){store.clear()}}message:{Text("Music is removed from this Watch. Send a fresh mix from your iPhone to listen again.")}
    }
}
struct WatchVolume:WKInterfaceObjectRepresentable{
    func makeWKInterfaceObject(context:Context)->WKInterfaceVolumeControl{WKInterfaceVolumeControl(origin:.local)}
    func updateWKInterfaceObject(_ object:WKInterfaceVolumeControl,context:Context){}
}
