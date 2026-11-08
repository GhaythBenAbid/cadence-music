import Foundation
import SwiftUI
import WatchKit
import WatchConnectivity
import CadenceCore

@MainActor final class WatchStore:ObservableObject{
    static let shared=WatchStore()
    let local=LocalLibrary()
    let bridge=WatchBridge()
    let audio=AudioController()
    @Published var isDemo=false
    init(){
        bridge.onMix={ [weak self] mix in do{try self?.local.accept(mix);self?.prepareAudio()}catch{self?.local.message=error.localizedDescription} }
        bridge.libraryProvider={ [weak self] in self?.local.receiptSnapshot ?? WatchMixLibraryReceipt(accountKey:nil,mixes:[]) }
        bridge.onRemoveMix={ [weak self] removal in do{if self?.local.mix?.id==removal.id{self?.audio.stop()};if try self?.local.remove(removal)==true{self?.prepareAudio()};self?.bridge.publishMixLibrary()}catch{self?.local.message=error.localizedDescription} }
        bridge.onClear={ [weak self] stamp in if self?.local.clear(at:stamp)==true { self?.audio.stop() } }
        let activity=bridge.inboundWork
        bridge.onFile={ [weak self] url,payload,ticket in
            guard let self else{return}
            await self.local.receive(url,payload:payload,shouldContinue:{!activity.isCancelled(ticket)});self.prepareAudio()
        }
        local.onReplace={ [weak self] in self?.audio.pause();self?.audio.persist() }
        local.onReceipt={ [weak self] receipt in self?.bridge.sendReceipt(receipt) }
        bridge.onActivation={ [weak self] in self?.local.acknowledge();self?.bridge.publishMixLibrary();self?.bridge.requestMix() }
        prepareAudio();resumeInbox()
        if ProcessInfo.processInfo.arguments.contains("--demo"){enterDemo()}
    }
    private func prepareAudio(){audio.configureSession(account:local.mix.map{$0.accountKey+":"+$0.id},resolver:{[weak self] in self?.local.localURL($0)},artwork:{[weak self] in self?.local.artwork($0)})}
    func play(_ song:Song?=nil){
        prepareAudio()
        if bridge.phonePlayback?.isPlaying==true && bridge.phoneReachable{bridge.control(.pause)}
        let songs=local.readySongs
        audio.play(songs,startingAt:song,resolver:{[weak self] in self?.local.localURL($0)})
    }
    func enterDemo(){
        do{
            isDemo=true
            let mix=try RunMix(accountKey:"cadence-demo",name:"Easy Miles · Demo",songs:DemoLibrary.songs)
            try local.accept(mix)
            for song in mix.songs{
                if let source=DemoLibrary.url(song){let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.copyItem(at:source,to:temp);_ = try local.cache(temp,song:song,account:mix.accountKey)}
            }
            prepareAudio()
        }catch{local.message=error.localizedDescription}
    }
    func selectMix(_ id:String){do{try local.select(id);prepareAudio()}catch{local.message=error.localizedDescription}}
    func removeMix(_ mix:RunMix){do{if local.mix?.id==mix.id{audio.stop()};_=try local.remove(WatchMixRemoval(mix));prepareAudio();bridge.publishMixLibrary()}catch{local.message=error.localizedDescription}}
    func clear(){audio.stop();local.clear();bridge.publishMixLibrary();isDemo=false}
    private func resumeInbox(){
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceInbox")
        for metadata in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] where metadata.pathExtension=="json"{
            guard let data=try? Data(contentsOf:metadata),let payload=try? JSONDecoder().decode(TrackTransfer.self,from:data) else{continue}
            let staged=metadata.deletingPathExtension()
            let activity=bridge.inboundWork,ticket=activity.begin()
            Task{defer{bridge.inboundWork.end(ticket);WatchBackgroundTracker.shared.refresh()};await local.receive(staged,payload:payload,shouldContinue:{!activity.isCancelled(ticket)});prepareAudio();if !FileManager.default.fileExists(atPath:staged.path){try? FileManager.default.removeItem(at:metadata)}}
        }
    }
}
@MainActor final class WatchBackgroundTracker {
    static let shared=WatchBackgroundTracker()
    private let gate:BackgroundDeliveryGate
    private var taskIDs:[ObjectIdentifier:UUID]=[:]
    private init(){
        let bridge=WatchStore.shared.bridge
        gate=BackgroundDeliveryGate(activity:bridge.inboundWork)
        bridge.onInboundWorkChanged={ [weak self] in self?.refresh() }
    }
    func refresh(){
        let bridge=WatchStore.shared.bridge
        gate.refresh(activated:bridge.didFinishActivation,contentPending:WCSession.default.hasContentPending)
    }
    func hold(_ task:WKRefreshBackgroundTask){
        let object=ObjectIdentifier(task)
        guard taskIDs[object]==nil else{return}
        let id=gate.hold{[weak self] in self?.taskIDs.removeValue(forKey:object);task.setTaskCompletedWithSnapshot(false)}
        taskIDs[object]=id
        // At the OS deadline, staged files and sidecars remain recoverable on the next wake.
        task.expirationHandler={ [weak self] in Task{@MainActor in WatchStore.shared.bridge.inboundWork.cancelAll();self?.gate.expire(id)} }
        refresh()
    }
}
@MainActor final class WatchDelegate:NSObject,WKApplicationDelegate {
    func applicationDidFinishLaunching(){_ = WatchStore.shared;_ = WatchBackgroundTracker.shared}
    func handle(_ backgroundTasks:Set<WKRefreshBackgroundTask>){
        _ = WatchStore.shared
        for task in backgroundTasks{
            if task is WKWatchConnectivityRefreshBackgroundTask{WatchBackgroundTracker.shared.hold(task)}
            else if let snapshot=task as? WKSnapshotRefreshBackgroundTask{snapshot.setTaskCompleted(restoredDefaultState:false,estimatedSnapshotExpiration:.distantFuture,userInfo:nil)}
            else{task.setTaskCompletedWithSnapshot(false)}
        }
    }
}
