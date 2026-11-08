import Foundation
import SwiftUI
import CadenceCore

@MainActor final class LocalLibrary:ObservableObject {
    @Published private(set) var mix:RunMix?
    @Published private(set) var mixes:[RunMix]=[]
    @Published private(set) var readyIDs:Set<String>=[]
    @Published var message:String?
    var onReplace:(()->Void)?
    var onReceipt:((WatchReceipt)->Void)?
    let root:URL
    private var clearedAt:Date
    private var accountBarrier=Date.distantPast
    private var removed:[String:Date]=[:]
    private var lastAccount:String?
    private var readable=true
    private let pruneUnused:Bool
    nonisolated static var defaultPrunes:Bool{
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
    private let preferences:UserDefaults
    private struct Index:Codable{var version=2;var mixes:[RunMix];var selectedID:String?;var removed:[String:Date];var accountBarrier:Date;var accountKey:String?}
    init(root customRoot:URL?=nil,preferences:UserDefaults = .standard,pruneUnused:Bool=LocalLibrary.defaultPrunes){
        self.preferences=preferences;self.pruneUnused=pruneUnused;root=customRoot ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Cadence",isDirectory:true)
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var values=URLResourceValues();values.isExcludedFromBackup=true;var location=root;try? location.setResourceValues(values)
        clearedAt=preferences.object(forKey:"lastClearedAt") as? Date ?? .distantPast
        if let data=try? Data(contentsOf:root.appendingPathComponent("mixes.json")),data.count<5_000_000,let index=try? JSONDecoder().decode(Index.self,from:data),index.version==2,index.mixes.count<=10,Set(index.mixes.map(\.id)).count==index.mixes.count,Set(index.mixes.map(\.accountKey)).count<=1,index.mixes.allSatisfy({(try? $0.validate()) != nil}){
            mixes=index.mixes.filter{$0.createdAt>clearedAt};mix=mixes.first{$0.id==index.selectedID} ?? mixes.first;removed=index.removed;accountBarrier=index.accountBarrier;lastAccount=index.accountKey ?? mix?.accountKey
        }else if FileManager.default.fileExists(atPath:root.appendingPathComponent("mixes.json").path){readable=false;message="The saved playlist index could not be read. Music files have been kept; clear saved music only if you want to reset it."}
        else if let data=try? Data(contentsOf:root.appendingPathComponent("mix.json")),let saved=try? JSONDecoder().decode(RunMix.self,from:data),(try? saved.validate()) != nil,saved.createdAt>clearedAt{mix=saved;mixes=[saved];lastAccount=saved.accountKey;try? persist()}
        refreshReady()
    }
    func url(for song:Song,account:String?=nil)->URL{root.appendingPathComponent(account ?? mix?.accountKey ?? "unassigned",isDirectory:true).appendingPathComponent(song.filename)}
    func localURL(_ song:Song)->URL?{let path=url(for:song);guard let bytes=try? path.resourceValues(forKeys:[.fileSizeKey]).fileSize,bytes>0 else{return nil};return path}
    func artworkURL(_ song:Song,account:String?=nil)->URL{url(for:song,account:account).appendingPathExtension("jpg")}
    func artwork(_ song:Song)->Data?{try? Data(contentsOf:artworkURL(song))}
    func select(_ id:String)throws{guard let selected=mixes.first(where:{$0.id==id}) else{throw CadenceError.message("That Watch playlist is no longer saved.")};if mix?.id != id{onReplace?();mix=selected;refreshReady();try persist();acknowledge()}}
    func accept(_ incoming:RunMix)throws{
        guard readable else{throw CadenceError.message("The saved Watch library needs recovery before receiving new playlists.")}
        try incoming.validate()
        guard incoming.createdAt>clearedAt,removed[incoming.id]==nil else{throw CadenceError.message("This mix was removed. Send a new mix from your iPhone.")}
        let latest=mixes.map(\.createdAt).max() ?? .distantPast
        let changingAccount=lastAccount.map{$0 != incoming.accountKey} ?? false
        guard !changingAccount || incoming.createdAt>max(latest,accountBarrier) else{throw CadenceError.message("An older account transfer was ignored.")}
        if incoming.keepOtherMixes != true,let current=mix,incoming.createdAt<current.createdAt{throw CadenceError.message("An older transfer was ignored. Your newer mix is safe.")}
        if incoming.keepOtherMixes==true,!changingAccount,mixes.contains(where:{$0.id==incoming.id})==false,mixes.count>=10{throw CadenceError.message("Your Watch has 10 saved playlists. Remove one before adding another.")}
        if let existing=mixes.first(where:{$0.id==incoming.id}){guard existing.accountKey==incoming.accountKey,existing.createdAt==incoming.createdAt,existing.songs==incoming.songs else{throw CadenceError.message("A changed transfer with the same playlist ID was ignored.")}}
        let old=mix
        if changingAccount{accountBarrier=incoming.createdAt;mixes=[];mix=nil;onReplace?();eraseAudioExcept(incoming.accountKey)}
        lastAccount=incoming.accountKey
        try FileManager.default.createDirectory(at:root.appendingPathComponent(incoming.accountKey),withIntermediateDirectories:true)
        if incoming.keepOtherMixes==true{
            if let i=mixes.firstIndex(where:{$0.id==incoming.id}){mixes[i]=incoming}else{mixes.append(incoming)}
            if mix==nil{mix=incoming}else if mix?.id==incoming.id{mix=incoming}
        }else{mixes=[incoming];mix=incoming}
        if !changingAccount,old?.id != mix?.id{onReplace?()}
        try persist();cleanupUnreferenced();refreshReady();acknowledge()
    }
    func cache(_ source:URL,song:Song,account:String)throws->URL{
        let target=url(for:song,account:account);try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:target.path){try FileManager.default.removeItem(at:target)}
        try FileManager.default.moveItem(at:source,to:target)
        var values=URLResourceValues();values.isExcludedFromBackup=true;var location=target;try? location.setResourceValues(values)
        refreshReady();return target
    }
    func receive(_ staged:URL,payload:TrackTransfer,shouldContinue:@escaping @Sendable()->Bool={true})async{
        var discard=true;defer{if discard{try? FileManager.default.removeItem(at:staged)}}
        do{
            try await Task.detached(priority:.utility){try FileIntegrity.verify(staged,transfer:payload,shouldContinue:shouldContinue)}.value
            try Task.checkCancellation();guard shouldContinue() else{throw CancellationError()}
            try accept(payload.mix)
            guard let song=payload.mix.songs.first(where:{$0.id==payload.songID}) else{return}
            _=try cache(staged,song:song,account:payload.mix.accountKey)
            if let artwork=payload.artwork,artwork.count<=12000{try? artwork.write(to:artworkURL(song,account:payload.mix.accountKey),options:.atomic)}
            message=nil;acknowledge(payload.mix)
        }catch is CancellationError{discard=false}catch{message=error.localizedDescription;acknowledge()}
    }
    func ready(_ value:RunMix)->[String]{value.songs.filter{song in let path=url(for:song,account:value.accountKey);return ((try? path.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)>0}.map(\.id)}
    func refreshReady(){readyIDs=Set(mix.map{ready($0)} ?? [])}
    func acknowledge(_ value:RunMix?=nil){if let value=value ?? mix{onReceipt?(WatchReceipt(mixID:value.id,accountKey:value.accountKey,readyIDs:ready(value),message:message))}}
    var receiptSnapshot:WatchMixLibraryReceipt{WatchMixLibraryReceipt(accountKey:mix?.accountKey,mixes:mixes.map{WatchSavedMix(mix:$0,readyIDs:ready($0))})}
    @discardableResult func remove(_ removal:WatchMixRemoval)throws->Bool{
        guard let value=mixes.first(where:{$0.id==removal.id}),value.accountKey==removal.accountKey,value.createdAt==removal.createdAt,removal.removedAt>=value.createdAt else{return false}
        removed[value.id]=removal.removedAt;accountBarrier=max(accountBarrier,value.createdAt);mixes.removeAll{$0.id==value.id}
        if mix?.id==value.id{onReplace?();mix=mixes.last}
        try persist();cleanupUnreferenced();refreshReady();acknowledge();return true
    }
    @discardableResult func clear(at stamp:Date=Date())->Bool{
        guard stamp>=clearedAt,mixes.allSatisfy({stamp >= $0.createdAt}) else{return false}
        let previous=mix;clearedAt=stamp;preferences.set(stamp,forKey:"lastClearedAt");onReplace?();mix=nil;mixes=[];removed=[:];readable=true;eraseFiles();readyIDs=[];message=nil
        if let previous{onReceipt?(WatchReceipt(mixID:previous.id,accountKey:previous.accountKey,readyIDs:[],message:"Saved Watch music was removed. Send it again to listen offline."))};return true
    }
    private func persist()throws{
        let index=Index(mixes:mixes,selectedID:mix?.id,removed:removed,accountBarrier:accountBarrier,accountKey:lastAccount)
        try JSONEncoder().encode(index).write(to:root.appendingPathComponent("mixes.json"),options:.atomic)
        if let mix{try JSONEncoder().encode(mix).write(to:root.appendingPathComponent("mix.json"),options:.atomic)}else{try? FileManager.default.removeItem(at:root.appendingPathComponent("mix.json"))}
    }
    private func cleanupUnreferenced(){
        guard pruneUnused else{return}
        guard let account=mix?.accountKey else{eraseAudioExcept(nil);return}
        let allowed=Set(mixes.flatMap{$0.songs}.flatMap{[$0.filename,$0.filename+".jpg"]})
        for file in (try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(account),includingPropertiesForKeys:nil)) ?? [] where !allowed.contains(file.lastPathComponent){try? FileManager.default.removeItem(at:file)}
    }
    private func eraseAudioExcept(_ account:String?){for file in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] where file.hasDirectoryPath && file.lastPathComponent != account{try? FileManager.default.removeItem(at:file)}}
    private func eraseFiles(){for path in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []{try? FileManager.default.removeItem(at:path)}}
    var readySongs:[Song]{(mix?.songs ?? []).filter{readyIDs.contains($0.id)}}
}
