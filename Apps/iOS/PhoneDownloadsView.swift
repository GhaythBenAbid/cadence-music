import SwiftUI
import UIKit
import CadenceCore

struct PhoneDownloadButton:View {
    @EnvironmentObject var store:PhoneStore
    let song:Song
    @ObservedObject var downloads:DeviceDownloads
    var showTitle=false
    @State private var remove=false
    var body:some View{
        Button{
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
            if downloads.contains(song){remove=true}else if let job=store.downloadManager.jobs.first(where:{$0.song.id==song.id}){store.downloadManager.retry(job.id)}else{store.download([song])}
        }label:{
            if store.downloading.contains(song.id){ProgressView().controlSize(.small).frame(width:30,height:44)}
            else if showTitle{Label(downloads.contains(song) ? "Downloaded on iPhone" : "Download to iPhone",systemImage:downloads.contains(song) ? "checkmark.circle.fill" : "arrow.down.circle")}
            else{Image(systemName:downloads.contains(song) ? "checkmark.circle.fill" : "arrow.down.circle").frame(width:30,height:44)}
        }.buttonStyle(.plain).foregroundStyle(Palette.ink).disabled(store.downloading.contains(song.id))
        .accessibilityLabel(downloads.contains(song) ? "Remove download for \(song.title)" : "Download \(song.title) to iPhone")
        .confirmationDialog("Remove this iPhone download?",isPresented:$remove,titleVisibility:.visible){Button("Remove download",role:.destructive){do{try downloads.remove(song)}catch{store.error=error.localizedDescription}}}message:{Text("The song stays in your Aurral library and Watch mix.")}
    }
}
struct PhoneDownloadsView:View {
    @EnvironmentObject var store:PhoneStore
    @ObservedObject var downloads:DeviceDownloads
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:22){
            SectionLabel(text:"Saved on this iPhone")
            Text("Music for\nthe way out.").font(.system(size:42,weight:.medium,design:.serif)).tracking(-1)
            Text("\(downloads.songs.count) tracks · ready without an internet connection").font(.subheadline).foregroundStyle(Palette.muted)
            DownloadJobsView(manager:store.downloadManager)
            if downloads.songs.isEmpty{ContentUnavailableView("Take your music with you",systemImage:"arrow.down.circle",description:Text("Tap the download arrow beside a song, or Download to iPhone on an album or playlist."))}
            else{
                Button{store.play(downloads.songs)}label:{Label("Play downloads",systemImage:"play.fill")}.buttonStyle(PrimaryButton())
                LazyVStack(spacing:2){ForEach(downloads.songs){song in SongRow(song:song){store.play(downloads.songs,startingAt:song)}}}
            }
        }.padding(24)}.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
    }
}

struct DownloadJobsView:View {
    @ObservedObject var manager:PhoneDownloadManager
    var body:some View{VStack(alignment:.leading,spacing:12){Toggle("Allow cellular for new downloads",isOn:$manager.cellular).font(.caption);ForEach(manager.jobs){job in VStack(alignment:.leading,spacing:6){HStack{Text(job.song.title).font(.subheadline);Spacer();if job.state == .running || job.state == .queued{Button("Pause"){manager.pause(job.id)}}else{Button(job.state == .failed ? "Retry" : "Resume"){manager.retry(job.id)}};Button("Cancel",role:.destructive){manager.cancel(job.id)}};if job.state == .running{ProgressView(value:job.progress)};Text(job.message ?? (job.state == .running ? "Downloading · \(Int(job.progress*100))% · waiting for a connection if needed" : job.state.rawValue.capitalized)).font(.caption).foregroundStyle(.secondary)}}}}
}
