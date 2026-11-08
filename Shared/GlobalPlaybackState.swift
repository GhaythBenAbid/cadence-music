#if os(iOS) || os(macOS)
import Foundation
import SwiftUI
import CadenceCore

@MainActor final class GlobalPlaybackState:ObservableObject {
    @Published private(set) var track:MusicCatalogEntry?
    @Published private(set) var message:String?
    @Published private(set) var waiting=false
    private var task:Task<Void,Never>?
    private var generation=UUID()
    private var account:String?
    func configure(_ account:String?){guard self.account != account else{return};reset();self.account=account}
    // Retain uncertain submissions for this session: Play again checks instead of submitting twice.
    private var requests:[String:String]=[:]
    func reset(){stopWaiting();requests=[:];track=nil;message=nil}
    func stopWaiting(){generation=UUID();task?.cancel();task=nil;waiting=false;if track != nil{message="Stopped waiting. An accepted request can still finish in Aurral."}}
    func start(_ track:MusicCatalogEntry,lookup:@escaping()async throws->Song?,request:@escaping()async throws->TrackPreparationReceipt,jobs:@escaping()async throws->[TrackPreparationJob],isCurrent:@escaping()->Bool,play:@escaping(Song)->Void,interval:Duration = .seconds(2),checks:Int=60){
        stopWaiting();self.track=track;message="Checking your library…";waiting=true;let stamp=generation
        task=Task{[weak self] in
            guard let self else{return}
            defer{if stamp==self.generation{self.waiting=false;self.task=nil}}
            do{
                if let song=try await lookup(){try Task.checkCancellation();guard stamp==generation,isCurrent() else{return};message="Playing "+track.title;waiting=false;play(song);return}
                try Task.checkCancellation();guard stamp==generation,isCurrent() else{return}
                var jobID=requests[track.id]
                if jobID==nil{
                    // Mark before sending: a cancelled or lost response must never cause an automatic resubmission.
                    requests[track.id]="";message="Asking Aurral to prepare this song…"
                    let receipt=try await request();jobID=receipt.jobId;requests[track.id]=jobID ?? ""
                }
                for _ in 0..<checks{
                    try Task.checkCancellation();guard stamp==generation,isCurrent() else{message="Playback changed. The song can still finish preparing in Aurral.";return}
                    if let song=try await lookup(){try Task.checkCancellation();guard stamp==generation,isCurrent() else{return};message="Playing "+track.title;waiting=false;play(song);return}
                    if let jobID,!jobID.isEmpty,let job=(try? await jobs())?.first(where:{$0.id==jobID}){message=job.message;if job.terminal{return}}
                    else{message="Waiting for the song to become available in Aurral…"}
                    try await Task.sleep(for:interval)
                }
                message="Still preparing in Aurral. Press Play again to check; it won't submit another request during this session."
            }catch is CancellationError{}catch{if stamp==generation{message=(error as? GlobalMusicError)?.localizedDescription ?? "Couldn't check Aurral. Check your server connection and press Play again to check the existing request."}}
        }
    }
}
#endif
