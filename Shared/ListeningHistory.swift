#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

@MainActor final class ListeningHistory:ObservableObject {
    @Published private(set) var profile=ListeningProfile()
    private var account:String?
    private let storage:ListeningProfileStore
    init(storage:ListeningProfileStore=ListeningProfileStore()){self.storage=storage}
    func configure(_ account:String?){guard self.account != account else{return};self.account=account;profile=account.map{storage.load($0)} ?? ListeningProfile()}
    func record(_ event:ListeningEntry,account eventAccount:String?){guard let account,eventAccount==account else{return};profile.record(event);save()}
    func follow(_ entry:MusicCatalogEntry){profile.follow(entry);save()}
    func bookmark(_ entry:MusicCatalogEntry){profile.save(entry);save()}
    func unbookmark(_ id:String){profile.unsave(id);save()}
    func clearHistory(){profile.history=[];save()}
    func erase(){if let account{storage.clear(account)};profile=ListeningProfile()}
    private func save(){if let account{storage.save(profile,account:account)}}
}
struct ListeningHistoryView:View {
    @ObservedObject var history:ListeningHistory
    let model:DiscoveryModel
    let playback:PreparationCenter
    let play:(Song,Double)->Void
    let playGlobal:(MusicCatalogEntry)->Void
    var interaction:CatalogInteraction?=nil
    @State private var clear=false
    var body:some View{List{
        Section("Recently played"){
            if history.profile.recent.isEmpty{Text("Songs appear here after you listen. History stays on this device.").foregroundStyle(.secondary)}
            ForEach(history.profile.recent){event in
                HStack{VStack(alignment:.leading){Text(event.song.title);Text(event.song.subtitle).font(.caption).foregroundStyle(.secondary)};Spacer();Button("Play"){play(event.song,0)};if event.position>5,event.position<Double(event.song.duration ?? 0)-5{Button("Resume"){play(event.song,event.position)}}}.accessibilityIdentifier("history."+event.song.id)
            }
        }
        Section("Saved from the catalog"){
            if history.profile.savedCatalog.isEmpty{Text("Save a catalog song before its audio is ready.").foregroundStyle(.secondary)}
            GlobalCatalogRows(entries:history.profile.savedCatalog,model:model,playback:playback,play:playGlobal,interaction:interaction)
        }
        Section("Artists you follow"){
            if history.profile.followedArtists.isEmpty{Text("Follow artists from global search to influence your library mix.").foregroundStyle(.secondary)}
            ForEach(history.profile.followedArtists){artist in HStack{NavigationLink(artist.title){GlobalCatalogDetail(entry:artist,model:model,playback:playback,play:playGlobal,interaction:interaction)};Button("Unfollow"){history.follow(artist)}}}
        }
    }.navigationTitle("Your listening").toolbar{Button("Clear history",role:.destructive){clear=true}}.confirmationDialog("Clear listening history on this device?",isPresented:$clear){Button("Clear history",role:.destructive){history.clearHistory()}}}
}
#endif
