import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import CadenceCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor final class AudioController: ObservableObject {
    @Published var current: Song?
    @Published var isPlaying = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var isShuffled = false
    @Published var repeatMode:RepeatMode = .off {didSet{if repeatMode != .off{relatedTask?.cancel();relatedTask=nil;suggestionTask?.work.cancel();suggestionTask=nil;preparingRelated=false};prepareNext();persist()}}
    var repeats:Bool{get{repeatMode != .off}set{repeatMode=newValue ? .all : .off}}
    @Published var autoplay=true {didSet{if !autoplay{relatedTask?.cancel();relatedTask=nil;suggestionTask?.work.cancel();suggestionTask=nil;preparingRelated=false};persist()}}
    @Published private(set) var preparingRelated=false
    var relatedSongs:((Song)async throws->[Song])?
    var onListeningEvent:((String?,ListeningEntry)->Void)?
    private var listeningID=UUID().uuidString
    private var heardSeconds:Double=0
    private var lastAudiblePosition:Double?
    private var lastHistorySave:Double=0
    private var listeningStarted=Date()
    var systemRoute:((PhoneCommand?)->Bool)?
    private var relatedTask:Task<Void,Never>?
    private var suggestionTask:(entryID:String,work:Task<[Song],Error>)?
    private var recoveryTask:Task<Void,Never>?
    private var wantsPlayback=false
    private var retryCount=0
    private var prepared:(id:String,item:AVPlayerItem)?
    var preparedNextID:String?{prepared?.id}
    private var stallTask:Task<Void,Never>?
    private var playerStateObservation:NSKeyValueObservation?
    private var failureObserver:NSObjectProtocol?
    private var stallObserver:NSObjectProtocol?
    @Published var volume:Float=1 {didSet{player.volume=max(0,min(volume,1))}}
    @Published var error: String?
    private let player = AVQueuePlayer()
    #if !os(macOS)
    // Retain the session for the lifetime of playback, including wrist-down transitions.
    private let audioSession=AVAudioSession.sharedInstance()
    #if os(watchOS)
    private var watchSessionActive=false
    #endif
    #endif
    @Published private(set) var timeline=PlaybackQueue()
    var upcoming:[QueueEntry]{timeline.upcoming}
    private var persistenceAccount:String?
    private let sessions:PlaybackSessionStore
    private var lastSave=Date.distantPast
    private var pendingSeek:Double?
    private var seeking=false
    private var seekSequence=0
    private var playbackIntent=0
    var playbackRevision:Int{playbackIntent}
    private var resolver: ((Song) -> URL?)?
    private var artworkResolver: ((Song) -> Data?)?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver:NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var wantsResume = false

    init(sessions:PlaybackSessionStore=PlaybackSessionStore()) {
        self.sessions=sessions
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        playerStateObservation=player.observe(\.timeControlStatus,options:[.new]){[weak self] player,_ in
            Task{@MainActor in guard let self,player.timeControlStatus == .playing else{return};self.stallTask?.cancel();self.stallTask=nil;if self.error?.hasPrefix("Buffering")==true{self.error=nil}}
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds:1,preferredTimescale:600), queue:.main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if self.pendingSeek==nil && !self.seeking{self.elapsed = time.seconds.isFinite ? max(0,time.seconds) : 0}
                if let value=self.player.currentItem?.duration.seconds, value.isFinite { self.duration=value }
                self.sampleListening(position:time.seconds,audible:self.player.timeControlStatus == .playing)
                self.prepareContinuation();self.updateNowPlaying();self.persist(force:false)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor in guard let self, let item=note.object as? AVPlayerItem, item === self.player.currentItem else { return }; self.finishedCurrent() }
        }
        failureObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemFailedToPlayToEndTime,object:nil,queue:.main){[weak self] note in
            let failure=note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            Task{@MainActor in guard let self,let item=note.object as? AVPlayerItem,item === self.player.currentItem else{return};self.handlePlaybackFailure(failure)}
        }
        stallObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemPlaybackStalled,object:nil,queue:.main){[weak self] note in
            Task{@MainActor in guard let self,self.isPlaying,let item=note.object as? AVPlayerItem,item === self.player.currentItem else{return};self.error="Buffering… Reconnecting to your music server."
                self.stallTask?.cancel();let intent=self.playbackIntent
                self.stallTask=Task{[weak self] in do{try await Task.sleep(for:.seconds(8));try Task.checkCancellation();guard let self,self.playbackIntent==intent,self.wantsPlayback,self.player.currentItem===item,self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else{return};self.handlePlaybackFailure(NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut))}catch{}}
            }
        }
        #if !os(macOS)
        interruptionObserver=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            let type=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options=note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.wantsResume=self.isPlaying
                    #if os(watchOS)
                    self.watchSessionActive=false
                    #endif
                    self.pause(userInitiated:false) }
                else{let shouldResume=self.wantsResume && AVAudioSession.InterruptionOptions(rawValue:options).contains(.shouldResume);self.wantsResume=false;if shouldResume{self.resume()}}
            }
        }
        #if os(watchOS)
        routeObserver=NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:audioSession,queue:.main){[weak self] note in
            guard note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else{return}
            Task{@MainActor in self?.watchSessionActive=false;self?.pause()}
        }
        #endif
        #endif
        let commands=MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.dispatchSystemCommand(PhoneCommand(.play)) }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.dispatchSystemCommand(PhoneCommand(.pause)) }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.dispatchSystemCommand(nil) }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.dispatchSystemCommand(PhoneCommand(.next)) }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.dispatchSystemCommand(PhoneCommand(.previous)) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event=event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.dispatchSystemCommand(PhoneCommand(.seek,value:event.positionTime)) }; return .success
        }
    }
    func sampleListening(position:Double,audible:Bool){
        guard position.isFinite,audible,current != nil else{lastAudiblePosition=nil;return}
        if let last=lastAudiblePosition{let delta=position-last;if delta>0,delta<2.5{heardSeconds+=delta}}
        lastAudiblePosition=position
        if heardSeconds-lastHistorySave>=10{flushListening()}
    }
    func flushListening(skipped:Bool=false){
        guard let current,heardSeconds>=1 else{return}
        onListeningEvent?(persistenceAccount,ListeningEntry(id:listeningID,song:current,date:listeningStarted,seconds:heardSeconds,position:elapsed,skipped:skipped));lastHistorySave=heardSeconds
    }
    func dispatchSystemCommand(_ command:PhoneCommand?){
        if systemRoute?(command)==true{return}
        if let command{try? apply(command)}else{toggle()}
    }
    func play(_ songs: [Song], startingAt song: Song? = nil, resolver: @escaping (Song) -> URL?, artwork: ((Song) -> Data?)? = nil,position:Double=0) {
        guard !songs.isEmpty else { return }
        flushListening(skipped:elapsed+5<duration);self.resolver=resolver; self.artworkResolver=artwork;timeline=PlaybackQueue(songs:songs,startingAt:song);isShuffled=false
        loadCurrent(position:position)
    }
    func resumeOrPlay(_ songs:[Song],resolver:@escaping(Song)->URL?,artwork:((Song)->Data?)?=nil){
        guard !songs.isEmpty else{return}
        let available=Set(songs.map(\.id))
        if let current,current.id==timeline.current?.song.id,timeline.entries.allSatisfy({available.contains($0.song.id)}){
            self.resolver=resolver;artworkResolver=artwork;resume()
        }else{play(songs,resolver:resolver,artwork:artwork)}
    }
    private func loadCurrent(autoplay:Bool=true,position:Double=0,recovering:Bool=false) {
        if !recovering{flushListening();listeningID=UUID().uuidString;heardSeconds=0;lastHistorySave=0;listeningStarted=Date()};lastAudiblePosition=nil
        suggestionTask?.work.cancel();suggestionTask=nil;stallTask?.cancel();stallTask=nil;recoveryTask?.cancel();recoveryTask=nil;relatedTask?.cancel();relatedTask=nil;preparingRelated=false
        seeking=false;seekSequence+=1
        if !recovering{retryCount=0}
        guard let entry=timeline.current else{return};let song=entry.song
        guard let url=resolver?(song) else { error="This track isn't ready yet. Finish downloading your mix."; pause(); return }
        error=nil; current=song; elapsed=position; duration=Double(song.duration ?? 0);pendingSeek=position>0 ? position : nil
        let item:AVPlayerItem
        if let cached=prepared,cached.id==entry.id,player.items().contains(where:{$0===cached.item}){
            player.advanceToNextItem();item=cached.item
        }else{
            player.removeAllItems();item=AVPlayerItem(url:url);item.preferredForwardBufferDuration=10;player.insert(item,after:nil)
        }
        prepared=nil
        statusObservation=item.observe(\.status,options:[.initial,.new]) { [weak self] item,_ in
            Task { @MainActor in
                guard let self,self.player.currentItem === item else{return}
                if item.status == .failed{self.handlePlaybackFailure(item.error as NSError?)}
                if item.status == .readyToPlay{self.error=nil;let length=item.duration.seconds;if length.isFinite{self.duration=max(0,length)};if let position=self.pendingSeek{self.pendingSeek=nil;self.seek(position)}}
            }
        }
        if autoplay{resume()}else{player.pause();isPlaying=false};prepareNext();updateNowPlaying();persist()
    }
    func toggle() { isPlaying ? pause() : resume() }
    func resume() {
        recoveryTask?.cancel();recoveryTask=nil;relatedTask?.cancel();relatedTask=nil;preparingRelated=false
        guard current != nil else { return };if player.currentItem?.status == .failed{retryCurrent();return};wantsPlayback=true;playbackIntent+=1;let intent=playbackIntent
        #if os(macOS)
        player.play();isPlaying=true;updateNowPlaying()
        #else
        do {
            let session=audioSession
            #if os(watchOS)
            // Moving to the next saved song keeps the established background audio route.
            if watchSessionActive && isPlaying{player.play();isPlaying=true;updateNowPlaying();return}
            #endif
            try session.setCategory(.playback,mode:.default,policy:.longFormAudio)
            #if os(watchOS)
            session.activate(options:[]) { [weak self] success, _ in
                Task { @MainActor in
                    guard let self,self.playbackIntent==intent else { return }
                    if success { self.watchSessionActive=true;self.player.play(); self.isPlaying=true; self.updateNowPlaying() }
                    else { self.error="Connect your Bluetooth headphones to the Watch, then try Play again."; self.isPlaying=false }
                }
            }
            #else
            try session.setActive(true); player.play(); isPlaying=true; updateNowPlaying()
            #endif
        } catch { self.error="Audio is unavailable. Connect your headphones and try again." }
        #endif
    }
    func pause(userInitiated:Bool=true,preserveSuggestions:Bool=false) { flushListening();lastAudiblePosition=nil; if !seeking,pendingSeek==nil,current != nil{let actual=player.currentTime().seconds;if actual.isFinite{elapsed=max(0,actual)}};if !preserveSuggestions{suggestionTask?.work.cancel();suggestionTask=nil};wantsPlayback=false;stallTask?.cancel();stallTask=nil;recoveryTask?.cancel();recoveryTask=nil;relatedTask?.cancel();relatedTask=nil;preparingRelated=false;if userInitiated{wantsResume=false};playbackIntent+=1;player.pause(); isPlaying=false; updateNowPlaying();persist() }
    func next() {
        flushListening(skipped:elapsed+5<duration)
        if timeline.advance(repeating:repeats){loadCurrent()}else{finishedCurrent()}
    }
    func cycleRepeat(){repeatMode=repeatMode.next}
    func retryCurrent(){guard current != nil else{return};loadCurrent(position:elapsed)}
    func finishedCurrent(){
        flushListening()
        if repeatMode == .one{loadCurrent();return}
        if timeline.advance(repeating:repeatMode == .all){loadCurrent();return}
        let prefetched=suggestionTask?.entryID==timeline.current?.id ? suggestionTask?.work : nil
        pause(userInitiated:false,preserveSuggestions:true)
        guard autoplay,let provider=relatedSongs,let seed=current else{return}
        let intent=playbackIntent,entry=timeline.current?.id;preparingRelated=true
        relatedTask=Task{[weak self] in
            do{
                let candidates:[Song]
                if let prefetched{candidates=try await prefetched.value}else{candidates=try await provider(seed)}
                try Task.checkCancellation()
                guard let self,self.playbackIntent==intent,self.timeline.current?.id==entry else{return}
                let existing=Set(self.timeline.entries.map{$0.song.id});var seen=existing
                let fresh=candidates.filter{seen.insert($0.id).inserted}.prefix(30)
                self.preparingRelated=false;self.relatedTask=nil
                guard !fresh.isEmpty else{self.error="No more recommendations are available in your library.";return}
                self.timeline.trimHistory(keeping:100);for song in fresh{self.timeline.append(song)}
                if self.timeline.advance(repeating:false){self.loadCurrent()}
            }catch is CancellationError{}catch{guard let self,self.playbackIntent==intent else{return};self.preparingRelated=false;self.relatedTask=nil;self.error="Recommendations couldn't load. Your queue is saved; try a library mix when connected."}
        }
    }
    private func prepareContinuation(){
        guard autoplay,repeatMode == .off,wantsPlayback,timeline.upcoming.isEmpty,let entry=timeline.current,let provider=relatedSongs,duration>0,elapsed>=max(0,duration-20),suggestionTask?.entryID != entry.id else{return}
        suggestionTask?.work.cancel();let song=entry.song
        suggestionTask=(entry.id,Task{try await provider(song)})
    }
    func handlePlaybackFailure(_ failure:NSError?){
        guard current != nil else{return};player.pause();isPlaying=false;updateNowPlaying()
        guard recoveryTask==nil else{return}
        func transient(_ error:NSError?)->Bool{guard let error else{return false};if error.domain==NSURLErrorDomain && [-1001,-1003,-1004,-1005,-1009].contains(error.code){return true};return transient(error.userInfo[NSUnderlyingErrorKey] as? NSError)}
        guard wantsPlayback,transient(failure),retryCount<2 else{error="This song couldn't play. Retry it, skip it, or use a downloaded copy.";persist();return}
        retryCount+=1;error="Reconnecting (\(retryCount)/2)…";let intent=playbackIntent,id=timeline.current?.id,position=elapsed,attempt=retryCount
        recoveryTask=Task{[weak self] in
            do{try await Task.sleep(for:.milliseconds(attempt*750));try Task.checkCancellation();guard let self,self.playbackIntent==intent,self.timeline.current?.id==id else{return};self.recoveryTask=nil;self.loadCurrent(position:position,recovering:true)}catch{}
        }
    }
    private func prepareNext(){
        guard let currentItem=player.currentItem else{prepared=nil;return}
        let next=timeline.upcoming.first ?? (repeatMode == .all ? timeline.entries.first : nil)
        if repeatMode != .one,let prepared,prepared.id==next?.id{return}
        for item in player.items() where item !== currentItem{player.remove(item)};prepared=nil
        guard repeatMode != .one,let next,next.id != timeline.current?.id,let url=resolver?(next.song) else{return}
        let item=AVPlayerItem(url:url);item.preferredForwardBufferDuration=10
        if player.canInsert(item,after:currentItem){player.insert(item,after:currentItem);prepared=(next.id,item)}
    }
    func previous(){if elapsed>3{seek(0)}else{timeline.previous();loadCurrent()}}
    func seek(_ seconds: Double) { guard seconds.isFinite else { return };let position=max(0,min(seconds,max(duration,0)));seeking=true;seekSequence+=1;let sequence=seekSequence;player.seek(to:CMTime(seconds:position,preferredTimescale:600)){[weak self] _ in Task{@MainActor in guard let self,self.seekSequence==sequence else{return};self.seeking=false}}; elapsed=position; updateNowPlaying();persist(force:false) }
    func shuffle(){timeline.toggleShuffle();isShuffled=timeline.shuffled;prepareNext();persist()}
    func enqueueChecked(_ song:Song,next:Bool=false)throws{guard timeline.entries.count<1000 else{throw CadenceError.message("The queue is full (1,000 songs). Remove upcoming songs before adding more.")};enqueue(song,next:next)}
    func enqueue(_ song:Song,next:Bool=false){timeline.append(song,next:next);if current==nil{loadCurrent(autoplay:false)};prepareNext();persist()}
    func removeUpcoming(_ id:String){timeline.removeUpcoming(id);prepareNext();persist()}
    func clearUpcoming(){timeline.clearUpcoming();prepareNext();persist()}
    func moveUpcoming(from:Int,to:Int){timeline.moveUpcoming(from:from,to:to);prepareNext();persist()}
    func playEntry(_ id:String){if timeline.jump(to:id){loadCurrent()}}
    func configureSession(account:String?,resolver:@escaping(Song)->URL?,artwork:((Song)->Data?)?=nil){
        self.resolver=resolver;artworkResolver=artwork
        guard persistenceAccount != account else{return}
        persist();reset();persistenceAccount=account
        guard let account,let saved=sessions.load(account:account),!saved.queue.entries.isEmpty else{return}
        timeline=saved.queue;repeatMode=saved.repeatMode ?? (saved.repeats ? .all : .off);autoplay=saved.autoplay ?? true;volume=saved.volume;isShuffled=timeline.shuffled
        loadCurrent(autoplay:false,position:saved.position)
    }
    func persist(force:Bool=true){
        guard let account=persistenceAccount,force || Date().timeIntervalSince(lastSave)>=5 else{return}
        lastSave=Date();if force || heardSeconds-lastHistorySave>=5{flushListening()}
        guard !timeline.entries.isEmpty else{sessions.clear(account:account);return}
        try? sessions.save(PlaybackSnapshot(queue:timeline,position:pendingSeek ?? elapsed,repeats:repeats,volume:volume,repeatMode:repeatMode,autoplay:autoplay),account:account)
    }
    private func reset(){flushListening();heardSeconds=0;lastAudiblePosition=nil;seeking=false;seekSequence+=1;suggestionTask?.work.cancel();suggestionTask=nil;wantsPlayback=false;stallTask?.cancel();stallTask=nil;recoveryTask?.cancel();recoveryTask=nil;relatedTask?.cancel();relatedTask=nil;preparingRelated=false;prepared=nil;statusObservation=nil;playbackIntent+=1;player.pause();player.removeAllItems();current=nil;isPlaying=false;elapsed=0;duration=0;timeline=PlaybackQueue();isShuffled=false;pendingSeek=nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo=nil
    }
    func playbackSnapshot()->PlaybackSnapshot{
        let actual=player.currentTime().seconds
        let position=pendingSeek ?? (isPlaying && !seeking && actual.isFinite ? max(0,actual) : elapsed)
        return PlaybackSnapshot(queue:timeline,position:position,repeats:repeats,volume:volume,repeatMode:repeatMode,autoplay:autoplay)
    }
    func replaceQueue(_ snapshot:PlaybackSnapshot,expected:[String])throws{
        try snapshot.validate()
        guard timeline.entries.map(\.id)==expected,snapshot.queue.current?.id==timeline.current?.id else{throw CadenceError.message("The queue changed on another device. Try adding the song again.")}
        timeline=snapshot.queue;isShuffled=timeline.shuffled;prepareNext();persist()
    }
    func install(_ snapshot:PlaybackSnapshot,autoplay shouldPlay:Bool)throws{
        try snapshot.validate();guard !snapshot.queue.entries.isEmpty else{throw CadenceError.message("There is no queue to transfer.")}
        pause();timeline=snapshot.queue;repeatMode=snapshot.repeatMode ?? (snapshot.repeats ? .all : .off);autoplay=snapshot.autoplay ?? true;isShuffled=timeline.shuffled
        loadCurrent(autoplay:shouldPlay,position:snapshot.position)
    }
    func apply(_ command:PhoneCommand)throws {
        try command.validate()
        switch command.action {
        case .play:resume()
        case .pause:pause()
        case .next:next()
        case .previous:previous()
        case .seek:seek(command.value ?? 0)
        case .shuffle:if isShuffled != (command.value==1){shuffle()}
        case .repeatMode:repeats=command.value==1
        case .volume:volume=Float(command.value ?? 1)
        };persist()
    }
    func stop(){if let account=persistenceAccount{sessions.clear(account:account)};reset();resolver=nil;artworkResolver=nil}
    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String:Any] = [MPMediaItemPropertyTitle:current.title, MPMediaItemPropertyArtist:current.artist ?? "", MPMediaItemPropertyAlbumTitle:current.album ?? "", MPMediaItemPropertyPlaybackDuration:duration, MPNowPlayingInfoPropertyElapsedPlaybackTime:elapsed, MPNowPlayingInfoPropertyPlaybackRate:isPlaying ? 1.0 : 0.0]
        #if os(iOS)
        if let data=artworkResolver?(current), let image=UIImage(data:data) { info[MPMediaItemPropertyArtwork]=MPMediaItemArtwork(boundsSize:image.size) { _ in image } }
        #elseif os(macOS)
        if let data=artworkResolver?(current),let image=NSImage(data:data){info[MPMediaItemPropertyArtwork]=MPMediaItemArtwork(boundsSize:image.size){_ in image}}
        #endif
        let center=MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo=info
        #if os(macOS)
        // macOS has no AVAudioSession from which to infer system transport state.
        let state:MPNowPlayingPlaybackState=isPlaying ? .playing : .paused
        if center.playbackState != state{center.playbackState=state}
        #endif
    }
}
