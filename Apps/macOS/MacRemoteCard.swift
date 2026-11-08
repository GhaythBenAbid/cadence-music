import SwiftUI
import CadenceCore
import AppKit

struct MacRemoteCard:View {
    @ObservedObject var server:PrivateMacServer
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            Label("Watch & iPhone control",systemImage:"applewatch").font(.headline)
            Text(server.message).font(.callout).foregroundStyle(.secondary)
            if let endpoint=server.endpoint{
                Text(endpoint.host+":"+String(endpoint.port)).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                Button("Copy iPhone connection link"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(endpoint.connectionURL.absoluteString,forType:.string)}
                Text("In Cadence on iPhone, tap Playback devices beside the mini player. Your Mac should appear nearby; you can also paste this link. Choose either device to transfer the queue, or choose Mac on your Watch for remote control.").font(.caption).foregroundStyle(.secondary)
            }
            if server.phoneAvailable{Label("iPhone available for handoff",systemImage:"iphone")}
            else{Text("Open Cadence on iPhone to receive a transfer.").font(.caption)}
            if server.pendingInstruction != nil{ProgressView("Waiting for iPhone confirmation…")}
            Button("Check Tailscale connection"){server.refreshNetwork()}
        }.padding(18).background(MacPalette.lime.opacity(0.35),in:RoundedRectangle(cornerRadius:16))
    }
}
