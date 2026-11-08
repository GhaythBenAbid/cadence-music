import SwiftUI
import CadenceCore

struct MacConnectionView:View {
    @EnvironmentObject var store:PhoneStore
    @ObservedObject var client:PrivateMacClient
    @ObservedObject var discovery:MacDiscovery
    @State private var address=""
    @State private var checking=false
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            Label(client.endpoint?.name ?? "Connect your Mac",systemImage:"laptopcomputer").font(.headline)
            Text(client.status.connected ? "Connected · choose Mac in Cadence on your Watch." : "Open Cadence on your Mac and use the same Aurral account. Keep Tailscale on both devices.").font(.caption).foregroundStyle(Palette.muted)
            ForEach(discovery.devices){device in Button{try? client.select(device);check()}label:{Label(device.name,systemImage:client.endpoint?.id==device.id ? "checkmark.circle" : "laptopcomputer")}.disabled(store.playingOnMac && client.endpoint?.id != device.id)}
            if let message=discovery.message{Text(message).font(.caption).foregroundStyle(.secondary)}
            TextField("Mac connection link or 100.x.x.x",text:$address).textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote)
            Button("Connect Mac"){
                do{
                    if address.hasPrefix("cadence:"),let url=URL(string:address){try client.select(MacEndpoint.from(url))}
                    else{try client.select(MacEndpoint(id:UUID().uuidString,name:"My Mac",host:address.trimmingCharacters(in:.whitespacesAndNewlines)))}
                    check()
                }catch{store.error=error.localizedDescription}
            }.disabled(address.isEmpty || store.credentials==nil || store.playingOnMac || store.transferringPlayback)
            if client.endpoint != nil{
                HStack{Button(checking ? "Checking…" : "Check connection"){check()}.disabled(checking);Spacer();Button("Forget Mac",role:.destructive){client.forget()}.disabled(store.playingOnMac || store.transferringPlayback)}
                if let message=client.status.message{Text(message).font(.caption).foregroundStyle(.secondary)}
            }
            Text("The Watch sends Mac commands through this iPhone. After setup, the Mac connection works over your private Tailscale network; nearby discovery is only needed for setup.").font(.caption).foregroundStyle(Palette.muted)
        }.padding(.vertical,8)
    }
    private func check(){checking=true;Task{_=try? await client.fetch();checking=false}}
}
