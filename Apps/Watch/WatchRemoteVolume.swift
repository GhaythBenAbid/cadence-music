import SwiftUI

struct WatchRemoteVolume:View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    var value:Double
    var enabled:Bool
    var active:Bool
    var device:String
    var send:(Double)->Void
    @FocusState private var focused:Bool
    @State private var draft=1.0
    @State private var editing=false
    @State private var lastInput=Date.distantPast
    @State private var pending:Task<Void,Never>?
    private var canSend:Bool{active && enabled && phase == .active}
    private var crownFocus:Bool{canSend && !voiceOver && !editing}
    private var input:Binding<Double>{Binding(get:{draft},set:{change($0)})}
    var body:some View {
        Button{editing=true}label:{VStack(spacing:2){Image(systemName:draft==0 ? "speaker.slash.fill" : "speaker.wave.2.fill");Text("\(Int((draft*100).rounded()))%").font(.caption2.monospacedDigit())}.frame(width:50,height:50).contentShape(Rectangle())}
            .buttonStyle(.plain).disabled(!enabled)
            .focusable(crownFocus).focused($focused)
            .digitalCrownRotation(input,from:0,through:1,by:0.05,sensitivity:.low,isContinuous:false,isHapticFeedbackEnabled:true)
            .accessibilityLabel(device+" Cadence volume").accessibilityValue("\(Int((draft*100).rounded())) percent")
            .accessibilityHint("Turn the Digital Crown to adjust. Activate to open the volume slider.")
            .accessibilityAdjustableAction{direction in switch direction{case .increment:change(draft+0.05);case .decrement:change(draft-0.05);@unknown default:break}}
            .accessibilityIdentifier("watch.remote.volume")
            .sheet(isPresented:$editing){WatchRemoteVolumeEditor(value:input,device:device,enabled:canSend)}
            .onAppear{draft=clamp(value);focused=crownFocus}
            .onChange(of:crownFocus){_,wanted in focused=wanted}
            .onChange(of:canSend){_,allowed in if !allowed{pending?.cancel();editing=false}}
            .onChange(of:value){_,newValue in if Date().timeIntervalSince(lastInput)>1 && !editing{draft=clamp(newValue)}}
            .onDisappear{pending?.cancel();focused=false}
    }
    private func clamp(_ value:Double)->Double{value.isFinite ? min(1,max(0,value)) : 1}
    private func change(_ value:Double){
        guard canSend else{return}
        draft=clamp(value);lastInput=Date();pending?.cancel();let requested=draft
        // Coalesce Crown detents instead of flooding the companion with messages.
        pending=Task{@MainActor in
            do{try await Task.sleep(for:.milliseconds(150));try Task.checkCancellation();send(requested)}catch{}
        }
    }
}

private struct WatchRemoteVolumeEditor:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Binding var value:Double
    var device:String
    var enabled:Bool
    @FocusState private var focused:Bool
    var body:some View {
        NavigationStack{
            ScrollView{VStack(spacing:12){
                Text(device+" Cadence volume").font(.headline)
                Text("\(Int((value*100).rounded()))%").font(.title3.monospacedDigit())
                Slider(value:$value,in:0...1).focused($focused).disabled(!enabled).accessibilityLabel(device+" Cadence volume")
                Button("Done"){dismiss()}
            }}.navigationTitle("Volume")
        }.onAppear{focused = !voiceOver && enabled}
    }
}

#if DEBUG
struct WatchRemoteVolumeFixture:View {
    @State private var received=0.5
    var body:some View {
        NavigationStack{VStack(spacing:12){
            Text("Remote volume input").font(.headline)
            WatchRemoteVolume(value:received,enabled:true,active:true,device:"Fixture",send:{received=$0})
            Text("Applied \(Int((received*100).rounded())) percent").accessibilityIdentifier("watch.fixture.applied-volume")
        }}
    }
}
#endif
