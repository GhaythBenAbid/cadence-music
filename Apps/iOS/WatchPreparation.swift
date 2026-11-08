import Foundation
import SwiftUI
import UIKit
import CadenceCore

/// Downloads are system-owned. This durable plan advances when downloads or
/// WatchConnectivity wake the phone, without needing either music screen open.
@MainActor final class WatchPreparation:ObservableObject {
    @Published private(set) var plan:WatchPreparationPlan?
    @Published private(set) var message=""
    var preparedCount:Int{plan?.scheduledIDs.count ?? 0}
    var active:Bool{plan != nil}
    private let local:LocalLibrary
    private let transport:WatchMixSending
    private let available:(Song)->URL?
    private let requestDownloads:([Song])->Void
    private let artwork:(Song)->Data?
    private let digest:(URL)async throws->String
    private let file:URL
    private var account:String?
    private var worker:Task<Void,Never>?
    private var generation=UUID()
    private var needsPass=false
    private var reconcile=false

    init(local:LocalLibrary,transport:WatchMixSending,root:URL?=nil,available:@escaping(Song)->URL?,requestDownloads:@escaping([Song])->Void,artwork:@escaping(Song)->Data?={_ in nil},digest:@escaping(URL)async throws->String={url in try await Task.detached(priority:.utility){try FileIntegrity.sha256(url)}.value}){
        self.local=local;self.transport=transport;self.available=available;self.requestDownloads=requestDownloads;self.artwork=artwork;self.digest=digest
        file=(root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceWatchPreparation",isDirectory:true)).appendingPathComponent("pending.json")
        if let data=try? Data(contentsOf:file),let saved=try? JSONDecoder().decode(WatchPreparationPlan.self,from:data),(try? saved.validate()) != nil{plan=saved;message="Resuming your Watch sync"}
    }
    func configure(account:String?){
        if self.account != account{generation=UUID();worker?.cancel();worker=nil}
        self.account=account
        guard let saved=plan else{return}
        guard saved.mix.accountKey==account else{cancel();return}
        do{try local.accept(saved.mix);requestMissingDownloads();Task{await flush(reconcile:true)}}catch{cancel();message="That Watch mix was replaced or removed. Choose a new mix."}
    }
    func start(name:String,songs:[Song],account:String,existing:RunMix?=nil)throws{
        let unique=songs.reduce(into:[Song]()){result,song in if !result.contains(where:{$0.id==song.id}){result.append(song)}}
        guard existing != nil || local.mixes.isEmpty || transport.supportsMultipleMixes else{throw CadenceError.message("Open the updated Cadence app on your Watch before adding another playlist.")}
        guard existing != nil || local.mixes.count<10 else{throw CadenceError.message("Remove a saved Watch playlist before adding another (maximum 10). ")}
        let retained=existing.flatMap{transport.supportsMultipleMixes && transport.receipt(for:$0) != nil ? $0 : nil}
        var mix=try retained ?? RunMix(accountKey:account,name:name,songs:unique)
        guard mix.accountKey==account,mix.songs==unique else{throw CadenceError.message("Choose the saved playlist again before resending it.")}
        if transport.supportsMultipleMixes{mix.keepOtherMixes=true}
        cancel();self.account=account;transport.resetReceipt()
        if let existing,retained==nil{_=try local.remove(WatchMixRemoval(existing))}
        try local.accept(mix);try local.select(mix.id);plan=WatchPreparationPlan(mix:mix)
        do{try persist()}catch{plan=nil;throw error}
        message="Downloading music · you can leave Cadence"
        requestMissingDownloads();Task{await flush()}
    }
    private func requestMissingDownloads(){
        guard let plan,plan.mix.accountKey==account else{return}
        requestDownloads(plan.mix.songs.filter{local.localURL($0)==nil && available($0)==nil})
    }
    func receive(_ receipt:WatchReceipt?){
        guard let receipt,let plan,receipt.mixID==plan.mix.id,receipt.accountKey==plan.mix.accountKey else{return}
        let ready=Set(receipt.readyIDs).intersection(Set(plan.mix.songs.map(\.id)))
        if ready.count==plan.mix.songs.count{generation=UUID();worker?.cancel();worker=nil;self.plan=nil;try? FileManager.default.removeItem(at:file);message="Ready for your run"}
        else{message="\(ready.count) of \(plan.mix.songs.count) tracks saved on Watch"}
    }
    func transferFinished(_ payload:TrackTransfer?,success:Bool){
        guard let payload,plan?.mix.id==payload.mix.id,plan?.mix.accountKey==payload.mix.accountKey else{return}
        if !success{plan?.scheduledIDs.remove(payload.songID);try? persist();message="A transfer paused. Keep both devices nearby and retry Watch sync."}
    }
    func retry(){requestMissingDownloads();Task{await flush(reconcile:true)}}
    func cancel(){generation=UUID();worker?.cancel();worker=nil;needsPass=false;plan=nil;try? FileManager.default.removeItem(at:file);transport.cancelOutstanding();message="Watch sync stopped. iPhone downloads stay available."}
    func flush(reconcile:Bool=false)async{
        needsPass=true;self.reconcile = self.reconcile || reconcile
        if let worker{await worker.value;return}
        guard plan != nil else{needsPass=false;return}
        let stamp=generation
        let work=Task{[weak self] in
            guard let self else{return}
            while self.needsPass && self.generation==stamp && !Task.isCancelled{self.needsPass=false;await self.performPass(generation:stamp)}
        }
        worker=work;await work.value
        if generation==stamp{worker=nil}
    }
    private func performPass(generation stamp:UUID)async{
        guard let initial=plan,initial.mix.accountKey==account,local.mix?.id==initial.mix.id,transport.canTransfer else{return}
        let mix=initial.mix
        let background=UIApplication.shared.beginBackgroundTask(withName:"Stage Watch transfer"){[weak self] in Task{@MainActor in guard let self,self.generation==stamp else{return};self.worker?.cancel();self.message="Sync is saved and continues at the next background opportunity."}}
        defer{if background != .invalid{UIApplication.shared.endBackgroundTask(background)}}
        do{
            try check(stamp,mix:mix)
            let pending=transport.outstandingSongIDs(for:mix)
            let receipt=transport.receipt(for:mix)
            let ready=Set(receipt?.mixID==mix.id && receipt?.accountKey==mix.accountKey ? receipt?.readyIDs ?? [] : [])
            if reconcile{plan?.scheduledIDs.formIntersection(pending.union(ready));reconcile=false}
            plan?.scheduledIDs.formUnion(pending);try persist();try transport.sendMix(mix)
            for song in mix.songs{
                try check(stamp,mix:mix)
                if ready.contains(song.id) || plan?.scheduledIDs.contains(song.id)==true{continue}
                if local.localURL(song)==nil,let source=available(song){
                    let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    do{try FileManager.default.copyItem(at:source,to:temp);try check(stamp,mix:mix);_=try local.cache(temp,song:song,account:mix.accountKey)}catch{try? FileManager.default.removeItem(at:temp);throw error}
                }
                guard let target=local.localURL(song) else{continue}
                let bytes=try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                let hash=try await digest(target)
                try check(stamp,mix:mix)
                var payload=TrackTransfer(mix:mix,songID:song.id,bytes:Int64(bytes),sha256:hash)
                if let data=artwork(song),let image=UIImage(data:data){let renderer=UIGraphicsImageRenderer(size:CGSize(width:96,height:96));let thumbnail=renderer.image{_ in image.draw(in:CGRect(x:0,y:0,width:96,height:96))}.jpegData(compressionQuality:0.45);if let thumbnail,thumbnail.count<=12000{payload.artwork=thumbnail}}
                try transport.sendFile(target,payload:payload);plan?.scheduledIDs.insert(song.id);try persist()
            }
            try check(stamp,mix:mix)
            let scheduled=plan?.scheduledIDs.count ?? 0
            message=scheduled==mix.songs.count ? "Queued for Watch · transfers continue with the screens closed" : "Preparing \(scheduled) of \(mix.songs.count) · downloads continue in the background"
            receive(transport.receipt(for:mix))
        }catch is CancellationError{}catch{if generation==stamp{message="Watch sync is saved. Check storage and connection, then retry."}}
    }
    private func check(_ stamp:UUID,mix:RunMix)throws{try Task.checkCancellation();guard generation==stamp,account==mix.accountKey,plan?.mix.id==mix.id,local.mix?.id==mix.id else{throw CancellationError()}}
    private func persist()throws{
        guard let plan else{return};try plan.validate()
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(plan).write(to:file,options:.atomic)
        var values=URLResourceValues();values.isExcludedFromBackup=true;var folder=file.deletingLastPathComponent();try? folder.setResourceValues(values)
    }
}
