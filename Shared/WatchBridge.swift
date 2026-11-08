import Foundation
import SwiftUI
import WatchConnectivity
import CadenceCore

@MainActor final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate, WatchMixSending {
    @Published private(set) var status="Connecting to your Watch…"
    @Published private(set) var canTransfer=false
    @Published private(set) var queuedCount=0
    @Published private(set) var receipt: WatchReceipt?
    @Published private(set) var watchLibrary:WatchMixLibraryReceipt?
    var supportsMultipleMixes:Bool{watchLibrary?.version==2}
    var libraryProvider:(()->WatchMixLibraryReceipt)?
    var onRemoveMix:((WatchMixRemoval)->Void)?
    func receipt(for mix:RunMix)->WatchReceipt?{
        if let snapshot=watchLibrary{guard snapshot.accountKey==mix.accountKey,let saved=snapshot.mixes.first(where:{$0.id==mix.id}) else{return nil};return WatchReceipt(mixID:mix.id,accountKey:mix.accountKey,readyIDs:saved.readyIDs)}
        guard let receipt,receipt.mixID==mix.id,receipt.accountKey==mix.accountKey else{return nil};return receipt
    }
    func removeRemoteMix(_ mix:RunMix)throws{
        guard let session,session.activationState == .activated,supportsMultipleMixes else{throw CadenceError.message("Open the updated Watch app before managing multiple playlists.")}
        session.transferUserInfo(["removeMix":try JSONEncoder().encode(WatchMixRemoval(mix))])
    }
    @Published private(set) var transferError: String?
    @Published private(set) var macRemote=MacRemoteStatus()
    var macProvider:(()async->MacRemoteStatus)?
    var onMacCommand:((PhoneCommand)async throws->MacRemoteStatus)?
    @Published private(set) var phonePlayback:PhonePlayback?
    @Published private(set) var phoneReachable=false
    @Published private(set) var remoteError:String?
    var onCommand:((PhoneCommand)throws->PhonePlayback)?
    var playbackProvider:(()->PhonePlayback)?
    private var lastPublished=Date.distantPast
    private var playbackSignature=""
    private var processedCommands:[String]=[]
    var onMix: ((RunMix) -> Void)?
    var onClear: ((Date) -> Void)?
    var onFile: ((URL,TrackTransfer,UUID) async -> Void)?
    var onRequestMix: (() -> Void)?
    var onActivation: (() -> Void)?
    private(set) var didFinishActivation=false
    nonisolated let inboundWork=TransferActivity()
    var onInboundWorkChanged:(()->Void)?
    var onFileTransferFinished:((TrackTransfer?,Bool)->Void)?
    private var contentObservation:NSKeyValueObservation?
    private var session: WCSession?
    override init() {
        super.init()
        if WCSession.isSupported() { session = .default; session?.delegate=self
            contentObservation=session?.observe(\.hasContentPending,options:[.new]){[weak self] _,_ in Task{@MainActor in self?.onInboundWorkChanged?()}}
            session?.activate() }
        else { status="Watch transfers need a paired iPhone and Apple Watch." }
    }
    func refresh() {
        guard let session else { return }
        #if os(iOS)
        canTransfer=session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        status = !session.isPaired ? "Pair an Apple Watch to prepare a run mix." : !session.isWatchAppInstalled ? "Install Cadence on your Watch to send music." : session.activationState != .activated ? "Connecting to your Watch…" : session.isReachable ? "Your Watch is connected" : "Watch connected · transfers continue in the background"
        #else
        canTransfer=session.activationState == .activated
        status=session.isReachable ? "Your iPhone is connected" : "Music sync waits for your paired iPhone. Transfers are scheduled in the background."
        #endif
        phoneReachable=session.isReachable
        queuedCount=session.outstandingFileTransfers.count
    }
    func sendMix(_ mix: RunMix) throws {
        guard let session, session.activationState == .activated else { throw CadenceError.message("Watch connection isn't ready. Open Cadence on both devices and try again.") }
        try updateContext(["version":1,"mix":try JSONEncoder().encode(mix)])
    }
    func sendFile(_ file: URL, payload: TrackTransfer) throws {
        guard let session, canTransfer else { throw CadenceError.message("Install and open Cadence on your paired Watch first.") }
        try payload.validate()
        let data=try JSONEncoder().encode(payload)
        guard data.count <= 60000 else { throw CadenceError.message("This mix has too much metadata. Choose a smaller collection.") }
        session.transferFile(file,metadata:["version":1,"track":data])
        refresh()
    }
    func outstandingSongIDs(for mix:RunMix)->Set<String>{
        Set((session?.outstandingFileTransfers ?? []).compactMap{transfer in
            guard let data=transfer.file.metadata?["track"] as? Data,let payload=try? JSONDecoder().decode(TrackTransfer.self,from:data),payload.mix.id==mix.id,payload.mix.accountKey==mix.accountKey else{return nil};return payload.songID
        })
    }
    nonisolated private func receive(_ work:@escaping @MainActor()async->Void){
        let ticket=inboundWork.begin()
        Task{@MainActor in defer{self.inboundWork.end(ticket);self.onInboundWorkChanged?()};await work()}
    }
    func cancelOutstanding() { session?.outstandingFileTransfers.forEach{$0.cancel()};refresh() }
    func resetReceipt() { receipt=nil;transferError=nil }
    func clearRemote() {
        cancelOutstanding();resetReceipt()
        try? updateContext(["version":1,"clearAt":Date().timeIntervalSince1970])
    }
    func sendReceipt(_ receipt: WatchReceipt) {
        guard let session, session.activationState == .activated, let data=try? JSONEncoder().encode(receipt) else { return }
        var fields:[String:Any]=["version":1,"receipt":data]
        if let snapshot=libraryProvider?(),let encoded=try? JSONEncoder().encode(snapshot){fields["mixLibrary"]=encoded}
        try? updateContext(fields)
    }
    func publishMixLibrary(){if let snapshot=libraryProvider?(),let data=try? JSONEncoder().encode(snapshot){try? updateContext(["mixLibrary":data])}}
    private func updateContext(_ fields:[String:Any])throws {
        guard let session,session.activationState == .activated else{return}
        try session.updateApplicationContext(CompanionContext.update(session.applicationContext,fields:fields))
    }
    func sendPlayback(_ state:PhonePlayback){
        guard let session,session.activationState == .activated,let data=try? JSONEncoder().encode(state) else{return}
        let signature=(state.song?.id ?? "none")+String(state.isPlaying)
        if signature != playbackSignature || Date().timeIntervalSince(lastPublished)>20 {
            try? updateContext(["playback":data]);lastPublished=Date();playbackSignature=signature
        }
        if session.isReachable{session.sendMessage(["playback":data],replyHandler:nil,errorHandler:nil)}
    }
    func sendMacStatus(_ status:MacRemoteStatus){
        guard let session,session.activationState == .activated,let data=try? JSONEncoder().encode(status) else{return}
        // Request replies carry fresh state; context is only a fallback for a new Watch launch.
        try? updateContext(["macRemote":data])
    }
    func requestPlayback(target:String="phone"){
        refresh();guard let session,session.isReachable else{return}
        session.sendMessage(CompanionControlMessage.stateRequest(mac:target=="mac"),replyHandler:{[weak self] reply in
            Task{@MainActor in self?.process(reply)}
        },errorHandler:{[weak self] _ in Task{@MainActor in self?.remoteError="Open Cadence on your iPhone to reconnect."}})
    }
    func control(_ action:PhoneCommand.Action,value:Double?=nil,target:String="phone"){
        guard let session,session.isReachable else{remoteError="Your iPhone is out of reach. Choose Watch to play your saved mix.";return}
        let command=PhoneCommand(action,value:value)
        guard let message=try? CompanionControlMessage.command(command,mac:target=="mac") else{return}
        remoteError=nil
        session.sendMessage(message,replyHandler:{[weak self] reply in Task{@MainActor in self?.process(reply)}},errorHandler:{[weak self] _ in Task{@MainActor in self?.remoteError="The iPhone didn't confirm that action. Reconnect and try again."}})
    }
    func requestMix() {
        guard let session, session.isReachable else { refresh();return }
        session.sendMessage(["requestMix":true],replyHandler:nil) { _ in }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive{self.refresh();self.process(session.receivedApplicationContext);self.didFinishActivation=activationState == .activated;self.onActivation?()}
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.refresh();if session.isReachable {self.requestPlayback();if let state=self.playbackProvider?(){self.sendPlayback(state)}} } }
    nonisolated func session(_ session:WCSession,didReceiveUserInfo userInfo:[String:Any]){receive{self.process(userInfo)}}
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String:Any]) { receive{self.process(applicationContext)} }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String:Any]) { receive{self.process(message);if message["requestMix"] as? Bool == true{self.onRequestMix?()}} }
    nonisolated func session(_ session:WCSession,didReceiveMessage message:[String:Any],replyHandler:@escaping([String:Any])->Void){
        receive{
            if message["target"] as? String == "mac" {
                do{
                    let status:MacRemoteStatus
                    if let data=message["macCommand"] as? Data,data.count<=8192,let command=try? JSONDecoder().decode(PhoneCommand.self,from:data),let handler=self.onMacCommand{try command.validate();status=try await handler(command)}
                    else if message["requestMacPlayback"] as? Bool == true,let provider=self.macProvider{status=await provider()}
                    else{replyHandler(["remoteError":"Update Cadence on your iPhone for Mac control."]);return}
                    if let data=try? JSONEncoder().encode(status){replyHandler(["macRemote":data]);self.sendMacStatus(status)}else{replyHandler([:])}
                }catch{replyHandler(["remoteError":"The Mac didn't confirm that action. Check Tailscale and Cadence on the Mac."])}
                return
            }
            if let data=message["command"] as? Data,let command=try? JSONDecoder().decode(PhoneCommand.self,from:data){
                do{
                    let state:PhonePlayback?
                    if self.processedCommands.contains(command.id){state=self.playbackProvider?()}
                    else{state=try self.onCommand?(command);self.processedCommands.append(command.id);self.processedCommands=Array(self.processedCommands.suffix(50))}
                    if let state,let encoded=try? JSONEncoder().encode(state){replyHandler(["playback":encoded]);self.sendPlayback(state)}else{replyHandler(["remoteError":"Open Cadence on your iPhone first."])}
                }catch{replyHandler(["remoteError":error.localizedDescription])}
            }else if message["requestPlayback"] as? Bool == true,let state=self.playbackProvider?(),let data=try? JSONEncoder().encode(state){replyHandler(["playback":data])}
            else{replyHandler([:])}
        }
    }
    private func process(_ dictionary: [String:Any]) {
        if let data=dictionary["mixLibrary"] as? Data,data.count<=200000,let value=try? JSONDecoder().decode(WatchMixLibraryReceipt.self,from:data),(try? value.validate()) != nil,value.updatedAt >= (watchLibrary?.updatedAt ?? .distantPast){watchLibrary=value}
        if let data=dictionary["removeMix"] as? Data,data.count<=8192,let removal=try? JSONDecoder().decode(WatchMixRemoval.self,from:data){onRemoveMix?(removal)}
        if let data=dictionary["macRemote"] as? Data,let status=try? JSONDecoder().decode(MacRemoteStatus.self,from:data),status.checkedAt>=macRemote.checkedAt{macRemote=status;remoteError=nil}
        if let data=dictionary["playback"] as? Data,let state=try? JSONDecoder().decode(PhonePlayback.self,from:data){
            if phonePlayback.map({state.updatedAt >= $0.updatedAt}) ?? true {phonePlayback=state;remoteError=nil}
        }
        if let message=dictionary["remoteError"] as? String{remoteError=message}
        if let stamp=dictionary["clearAt"] as? Double { onClear?(Date(timeIntervalSince1970:stamp)) }
        if let data=dictionary["mix"] as? Data, let mix=try? JSONDecoder().decode(RunMix.self,from:data) { onMix?(mix) }
        if let data=dictionary["receipt"] as? Data, let value=try? JSONDecoder().decode(WatchReceipt.self,from:data) { receipt=value }
        refresh()
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let ticket=inboundWork.begin()
        guard let data=file.metadata?["track"] as? Data,data.count<300_000,let payload=try? JSONDecoder().decode(TrackTransfer.self,from:data),(try? payload.validate()) != nil else{inboundWork.end(ticket);Task{@MainActor in self.onInboundWorkChanged?()};return}
        do{
            let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceInbox")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let staged=root.appendingPathComponent(UUID().uuidString)
            try data.write(to:staged.appendingPathExtension("json"),options:.atomic)
            try FileManager.default.moveItem(at:file.fileURL,to:staged)
            Task{@MainActor in
                defer{self.inboundWork.end(ticket);self.onInboundWorkChanged?()}
                // Leave both files for recovery if launch-time consumers aren't attached yet.
                guard let onFile=self.onFile else{return}
                await onFile(staged,payload,ticket)
                if !FileManager.default.fileExists(atPath:staged.path){try? FileManager.default.removeItem(at:staged.appendingPathExtension("json"))}
            }
        }catch{inboundWork.end(ticket);Task{@MainActor in self.transferError="A music transfer couldn't be saved. Check storage and resend the mix.";self.onInboundWorkChanged?()}}
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task{@MainActor in
            self.refresh()
            let payload=(fileTransfer.file.metadata?["track"] as? Data).flatMap{try? JSONDecoder().decode(TrackTransfer.self,from:$0)}
            self.onFileTransferFinished?(payload,error==nil)
            if error != nil{self.transferError="A track didn't reach the Watch. Keep both devices nearby and retry the sync."}
        }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    #endif
}
