import SwiftUI
import CadenceCore

struct PlaybackDevicesView:View {
    @EnvironmentObject var store:PhoneStore
    @ObservedObject var client:PrivateMacClient
    @Environment(\.dismiss) private var dismiss
    @State private var busy=false
    @State private var localRecovery=false
    @State private var error:String?
    var body:some View{
        NavigationStack{List{
            Section("Play on"){
                Button{perform{try await store.continueOnPhone()}}label:{Label("This iPhone",systemImage:store.playingOnMac ? "iphone" : "checkmark.circle.fill")}.disabled((!store.playingOnMac && !store.hasUnconfirmedIncomingTransfer) || busy)
                if let endpoint=client.endpoint{
                    Button{perform{try await store.continueOnMac()}}label:{Label(endpoint.name,systemImage:store.playingOnMac ? "checkmark.circle.fill" : "laptopcomputer")}.disabled(store.playingOnMac || busy || store.audio.current==nil)
                    Text("Transfers the entire queue, repeat mode and playback position. Local files remain on their devices; the destination needs its own file or access to Aurral.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.hasUnconfirmedOutgoingTransfer{Button("Retry the unconfirmed transfer"){perform{try await store.retryOutgoingTransfer()}}.disabled(busy)}
            if busy || store.transferringPlayback{ProgressView("Transferring playback…")}
            if let error{Text(error).foregroundStyle(.secondary)}
            if let message=store.deviceMessage{Text(message).font(.caption).foregroundStyle(.secondary)}
            if store.playingOnMac,let playback=client.status.playback{
                Section("On your Mac"){
                    Text(playback.song?.title ?? "No song selected").font(.headline)
                    Text(playback.song?.artist ?? "").foregroundStyle(.secondary)
                    HStack{Button("Previous"){Task{await store.commandMac(PhoneCommand(.previous))}};Button(playback.isPlaying ? "Pause" : "Play"){Task{await store.commandMac(PhoneCommand(playback.isPlaying ? .pause : .play))}};Button("Next"){Task{await store.commandMac(PhoneCommand(.next))}}}.disabled(!client.status.connected)
                    Slider(value:Binding(get:{min(playback.elapsed,max(playback.duration,1))},set:{value in Task{await store.commandMac(PhoneCommand(.seek,value:value))}}),in:0...max(playback.duration,1)).disabled(!client.status.connected)
                    if !client.status.connected{Text("Mac disconnected. Controls are disabled until it reconnects.").font(.caption)}
                }
            }
            if store.playingOnMac && !client.status.connected{Button("Use this iPhone’s saved queue"){localRecovery=true}}
            Section("Connect a Mac"){MacConnectionView(client:client,discovery:store.macDiscovery)}
            Text("Keep both apps open and Tailscale connected. Receiving a handoff on iPhone requires Cadence in the foreground; this does not wake a suspended phone.").font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Use the saved iPhone queue?",isPresented:$localRecovery){Button("Use this iPhone"){store.useSavedPhoneQueue()}}message:{Text("The unreachable Mac cannot be stopped. Pause it first if it is still playing. This uses the iPhone’s saved queue, which may differ from the Mac’s latest queue.")}.navigationTitle("Playback devices").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}}
    }
    private func perform(_ work:@escaping()async throws->Void){Task{busy=true;error=nil;defer{busy=false};do{try await work()}catch{self.error=error.localizedDescription}}}
}
