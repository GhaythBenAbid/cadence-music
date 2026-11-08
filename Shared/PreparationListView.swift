#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

struct PreparationListView:View {
    @ObservedObject var center:PreparationCenter
    let resume:(String)->Void
    @State private var checking=false
    @State private var retryID:String?
    private func actionLabel(_ action:CatalogAction)->String{switch action{case .play:return "Play album / song";case .playNext:return "Play next";case .enqueue:return "Add to queue";case .favorite:return "Save to favorites";case .playlist:return "Add to playlist";case .download:return "Download"}}
    var body:some View{List{
        Section{Text("Accepted requests continue on Aurral when you leave. Reopening restores status checks; playback waits for your confirmation.").font(.caption).foregroundStyle(.secondary)}
        if let error=center.error{Text(error).foregroundStyle(.orange)}
        if center.items.isEmpty{ContentUnavailableView("Nothing preparing",systemImage:"checkmark.circle",description:Text("Choose Play, Add to queue or Save from All music."))}
        ForEach(Array(center.items.reversed())){item in
            VStack(alignment:.leading,spacing:8){
                HStack{VStack(alignment:.leading){Text(item.entry.title).font(.headline);Text(item.entry.artist).font(.caption).foregroundStyle(.secondary)};Spacer();if item.active{ProgressView()}}
                Text(actionLabel(item.action)).font(.caption.weight(.semibold))
                Text(item.message).font(.caption).foregroundStyle(.secondary)
                HStack{
                    if item.phase == .ready,item.reviewBeforeApplying{Button("Apply prepared music"){resume(item.groupID)}}
                    if [.uncertain,.blocked,.failed].contains(item.phase){Button("Check status"){center.checkAgain(item.id);Task{await center.sync()}}}
                    if [.failed,.uncertain].contains(item.phase){Button("Request again"){retryID=item.id}}
                    if [.failed,.uncertain,.blocked].contains(item.phase),let server=center.serverURL{Link("Review in Aurral",destination:server)}
                    if item.phase != .complete && item.phase != .stopped{Button("Remove",role:.destructive){center.remove(item.id)}}
                }.font(.caption).buttonStyle(.borderless)
            }.padding(.vertical,5).accessibilityIdentifier("preparation."+item.id)
        }
    }.navigationTitle("Preparing music").toolbar{
        Button("Refresh"){Task{checking=true;await center.sync();checking=false}}.disabled(checking || center.checking)
        Button("Clear completed"){center.clearCompleted()}
    }.confirmationDialog("Request this song again?",isPresented:Binding(get:{retryID != nil},set:{if !$0{retryID=nil}})){Button("Request again"){if let retryID{center.requestAgain(retryID);Task{await center.sync()}};retryID=nil}}message:{Text("An unconfirmed request may still exist in Aurral. Check it first. Playback will wait for you to apply the prepared music.")}}
}
#endif
