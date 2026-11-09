import SwiftUI
import Combine
import CadenceCore

struct WatchAmbientPlayer:View {
    @Environment(\.dynamicTypeSize) private var textSize
    let audio:AudioController
    let bridge:WatchBridge
    let source:String
    var showControls:()->Void
    @State private var song:Song?
    @State private var playing=false
    private typealias DisplayState=(Song?,Bool)
    private var device:String{source=="mac" ? "Mac" : source=="phone" ? "iPhone" : "Watch"}
    var body:some View {
        Button(action:showControls){content}
            .buttonStyle(.plain).accessibilityHint("Show playback controls").accessibilityIdentifier("watch.ambient")
            .onReceive(localState){value in if source=="watch"{update(value.0,playing:value.1)}}
            .onReceive(phoneState){value in if source=="phone"{update(value.0,playing:value.1)}}
            .onReceive(macState){value in if source=="mac"{update(value.0,playing:value.1)}}
    }
    private var content:some View {
        VStack(alignment:.leading,spacing:9){
            if textSize < .xxxLarge{Text("CADENCE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Color(white:0.5)).accessibilityHidden(true)}
            Text(song?.title ?? "No track selected").font(.headline).lineLimit(3).foregroundStyle(Color(white:0.6))
            if let song{Text(song.subtitle).font(.caption).lineLimit(1).foregroundStyle(Color(white:0.5))}
            Label(source=="watch" ? (playing ? "Playing on Watch" : "Paused on Watch") : "On "+device,systemImage:playing ? "play.fill" : "pause.fill").font(.caption2).foregroundStyle(Color(white:0.5))
            if textSize < .xxxLarge{Text("Raise wrist or tap for controls").font(.caption2).foregroundStyle(Color(white:0.5))}
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).padding(.horizontal,16).background(Color.black)
    }
    // Named, typed publishers keep the SwiftUI expression within older compiler limits.
    // Ignore elapsed-time ticks: the dimmed screen only needs track/playing changes.
    private var localState:AnyPublisher<DisplayState,Never>{
        audio.$current.combineLatest(audio.$isPlaying)
            .removeDuplicates{$0.0==$1.0 && $0.1==$1.1}.eraseToAnyPublisher()
    }
    private var phoneState:AnyPublisher<DisplayState,Never>{
        bridge.$phonePlayback.map{($0?.song,$0?.isPlaying ?? false)}
            .removeDuplicates{$0.0==$1.0 && $0.1==$1.1}.eraseToAnyPublisher()
    }
    private var macState:AnyPublisher<DisplayState,Never>{
        bridge.$macRemote.map{($0.playback?.song,$0.playback?.isPlaying ?? false)}
            .removeDuplicates{$0.0==$1.0 && $0.1==$1.1}.eraseToAnyPublisher()
    }
    private func update(_ value:Song?,playing running:Bool){
        if song != value{song=value}
        if playing != running{playing=running}
    }
}
