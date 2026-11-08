#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

/// Audio acquisition continues on Aurral; this bounded foreground worker restores checks,
/// never a playback intention, after an app relaunch.
@MainActor final class PreparationCenter:ObservableObject {
    @Published private(set) var items:[CatalogPreparation]=[]
    @Published private(set) var error:String?
    @Published private(set) var checking=false
    private var account:String?
    private var readable=true
    private var generation=UUID()
    private let storage:PreparationStore
    private var allowedGroups=Set<String>()
    private var lookup:((MusicCatalogEntry)async throws->Song?)?
    private var request:((MusicCatalogEntry)async throws->TrackPreparationReceipt)?
    private var jobs:(()async throws->[TrackPreparationJob])?
    var serverURL:URL?
    var hasPlaybackQueue:(()->Bool)?
    var apply:((CatalogPreparation)async throws->Void)?
    var waiting:Bool{items.contains{($0.active || $0.phase == .ready) && allowedGroups.contains($0.groupID)}}
    var track:MusicCatalogEntry?{items.last(where:{$0.phase != .complete})?.entry}
    var message:String?{error ?? items.last(where:{$0.phase != .complete})?.message}
    var pendingCount:Int{items.filter{$0.phase != .complete && $0.phase != .stopped}.count}
    init(storage:PreparationStore=PreparationStore()){self.storage=storage}
    func configure(_ account:String?,lookup:((MusicCatalogEntry)async throws->Song?)?=nil,request:((MusicCatalogEntry)async throws->TrackPreparationReceipt)?=nil,jobs:(()async throws->[TrackPreparationJob])?=nil){
        if self.account != account{
            generation=UUID();checking=false;allowedGroups=[];self.account=account;items=[];error=nil;readable=true
            if let account{do{items=try storage.read(account)}catch{readable=false;self.error="Saved preparation status could not be read. It has been kept; no requests will be sent."}}
            for i in items.indices{
                if items[i].phase == .submitting{items[i].phase = .uncertain;items[i].message="Request unconfirmed. Check its status before requesting again."}
                if items[i].phase == .applying{items[i].phase = .ready;items[i].reviewBeforeApplying=true;items[i].message="Prepared. Review before applying the saved action."}
                if [.play,.playNext,.enqueue].contains(items[i].action),items[i].phase != .complete{items[i].reviewBeforeApplying=true}
            }
            if readable{save()}
        }
        self.lookup=lookup;self.request=request;self.jobs=jobs
    }
    @discardableResult func submit(_ entries:[MusicCatalogEntry],action:CatalogAction,playlistID:String?=nil)throws->String{
        guard readable else{throw CadenceError.message("The saved preparation list needs recovery before adding requests.")}
        guard account != nil else{throw CadenceError.message("Sign in before preparing music.")}
        var seen=Set<String>();let unique=entries.filter{$0.kind == .song && seen.insert($0.id).inserted}
        guard !unique.isEmpty,unique.count<=200,items.filter({$0.phase != .complete && $0.phase != .stopped}).count+unique.count<=300 else{throw CadenceError.message("Choose up to 200 songs; finish or remove older preparation requests first.")}
        if action == .playlist && (playlistID ?? "").isEmpty{throw CadenceError.message("Choose a playlist first.")}
        let group=UUID().uuidString;allowedGroups.insert(group)
        // Repeated clicks check the existing unfinished action instead of creating another submission.
        if unique.count==1,let existing=items.first(where:{$0.entry.id==unique[0].id && $0.action==action && $0.playlistID==playlistID && $0.phase != .complete && $0.phase != .stopped}){allowedGroups.insert(existing.groupID);for i in items.indices where items[i].groupID==existing.groupID{items[i].reviewBeforeApplying=false};save();return existing.groupID}
        items += unique.enumerated().map{CatalogPreparation(groupID:group,index:$0.offset,entry:$0.element,action:action,playlistID:playlistID)}
        trim();try persist();return group
    }
    func stopWaiting(){
        for i in items.indices where [.play,.playNext,.enqueue].contains(items[i].action) && items[i].phase != .complete{items[i].reviewBeforeApplying=true;items[i].message="Preparation continues. Apply when you are ready."}
        allowedGroups=[];save()
    }
    func allow(_ group:String){allowedGroups.insert(group);for i in items.indices where items[i].groupID==group{items[i].reviewBeforeApplying=false};save()}
    func checkAgain(_ id:String){guard let i=items.firstIndex(where:{$0.id==id}) else{return};if [.blocked,.failed,.uncertain].contains(items[i].phase){items[i].phase = .uncertain;items[i].message="Checking the existing server request…"};save()}
    func requestAgain(_ id:String){guard let i=items.firstIndex(where:{$0.id==id}),[.failed,.uncertain].contains(items[i].phase) else{return};items[i].phase = .queued;items[i].jobID=nil;items[i].reviewBeforeApplying=true;items[i].message="Retry requested. Apply the music when ready.";save()}
    func remove(_ id:String){guard let i=items.firstIndex(where:{$0.id==id}) else{return};items[i].phase = .stopped;items[i].message="Removed from this list. Accepted server preparation can still finish.";save()}
    func clearCompleted(){items.removeAll{[.complete,.stopped].contains($0.phase)};save()}
    func erase(){if let account{storage.clear(account)};generation=UUID();items=[];allowedGroups=[];checking=false;readable=true;error=nil}
    func sync()async{
        guard readable,!checking,account != nil,let lookup,let request else{return}
        let stamp=generation;checking=true;defer{if generation==stamp{checking=false}}
        let serverJobs:[TrackPreparationJob]=(try? await jobs?()) ?? []
        guard generation==stamp else{return}
        // Two outstanding acquisitions at a time keeps album requests bounded.
        let running=items.filter{[.preparing,.submitting].contains($0.phase)}
        var selected=Array(running.prefix(2))
        if selected.count<2{selected += items.filter{$0.phase == .queued}.prefix(2-selected.count)}
        selected += items.filter{$0.phase == .uncertain}.sorted{($0.checkedAt ?? .distantPast)<($1.checkedAt ?? .distantPast)}.prefix(2)
        for value in selected{
            update(value.id){$0.checkedAt=Date()}
            guard generation==stamp,!Task.isCancelled else{return}
            do{
                if let song=try await lookup(value.entry){guard generation==stamp else{return};update(value.id){$0.song=song;$0.phase = .ready;$0.message="Ready"};continue}
                guard generation==stamp else{return}
                guard items.first(where:{$0.id==value.id})?.phase != .stopped else{continue}
                let job=serverJobs.first{$0.id==value.jobID || (value.phase == .uncertain && $0.matches(value.entry))}
                if let job{update(value.id){$0.jobID=job.id;$0.message=job.message;$0.phase=job.status=="blocked" ? .blocked : job.terminal ? .failed : .preparing};continue}
                if value.phase == .queued{
                    if let existing=items.first(where:{$0.id != value.id && $0.entry.id==value.entry.id && ([.preparing,.submitting,.uncertain].contains($0.phase)) && ($0.jobID != nil || $0.phase == .uncertain)}){
                        update(value.id){$0.jobID=existing.jobID;$0.phase=existing.jobID==nil ? .uncertain : .preparing;$0.message="Checking the existing song request…"};continue
                    }
                    // This write must reach disk before a network mutation.
                    update(value.id){$0.phase = .submitting;$0.message="Requesting preparation…"};try persist()
                    let result=try await request(value.entry);guard generation==stamp else{return}
                    update(value.id){$0.jobID=result.jobId;$0.phase = .preparing;$0.message="Waiting for Aurral audio…"}
                }else if value.phase == .uncertain{update(value.id){$0.message="No confirmed job found. Check Aurral before creating a new request."}}
            }catch{guard generation==stamp else{return};update(value.id){item in
                item.phase = item.phase == .submitting ? .uncertain : item.phase
                if let failure=error as? GlobalMusicError{item.message=failure.localizedDescription;if case .permission=failure{item.phase = .failed}}
                else{item.message="Couldn’t reach Aurral. Saved requests will be checked again when connected."}
            }}
        }
        guard generation==stamp else{return};await deliver(stamp:stamp);save()
    }
    private func deliver(stamp:UUID)async{
        guard let apply else{return}
        let groups=items.reduce(into:[String]()){if !$0.contains($1.groupID){$0.append($1.groupID)}}
        for group in groups{
            let ordered=items.filter{$0.groupID==group}.sorted{$0.index<$1.index}
            let next=ordered.first?.action == .playNext
            if next && !ordered.allSatisfy(\.resolved){continue}
            let reverse=next && (hasPlaybackQueue?() ?? true)
            for value in reverse ? ordered.reversed().map({$0}) : ordered{
                guard generation==stamp,!Task.isCancelled else{return}
                if [.complete,.blocked,.failed,.stopped].contains(value.phase){continue}
                if value.phase != .ready{break}
                if value.reviewBeforeApplying || ([.play,.playNext,.enqueue].contains(value.action) && !allowedGroups.contains(group)){continue}
                update(value.id){$0.phase = .applying;$0.message="Applying prepared song…"};save()
                do{var delivery=value;if next && !reverse{delivery.action = .enqueue};try await apply(delivery);guard generation==stamp else{return};update(value.id){$0.phase = .complete;$0.message="Done"}}
                catch{guard generation==stamp else{return};update(value.id){$0.phase = .ready;$0.reviewBeforeApplying=true;$0.message=(error as? CadenceError)?.localizedDescription ?? "Prepared. The action wasn't confirmed; review and apply again."}}
                save()
            }
        }
    }
    private func update(_ id:String,_ edit:(inout CatalogPreparation)->Void){guard let i=items.firstIndex(where:{$0.id==id}),items[i].phase != .stopped else{return};edit(&items[i]);save()}
    private func trim(){let pending=items.filter{![.complete,.stopped].contains($0.phase)};let past=items.filter{[.complete,.stopped].contains($0.phase)}.suffix(max(0,500-pending.count));items=Array(past)+pending}
    private func persist()throws{guard readable else{throw CadenceError.message("The saved list needs recovery.")};guard let account else{return};try storage.save(items,account:account)}
    private func save(){do{try persist()}catch{self.error="Preparation status couldn't be saved. Check storage before requesting more songs."}}
}
#endif
