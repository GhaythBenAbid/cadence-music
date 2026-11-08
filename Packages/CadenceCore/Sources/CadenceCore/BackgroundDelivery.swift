import Foundation

/// Delegate callbacks record work before hopping to MainActor, so a background wake
/// cannot be completed in the gap before a file import starts.
public final class TransferActivity: @unchecked Sendable {
    private let lock=NSLock()
    private var tickets=Set<UUID>()
    private var cancelled=Set<UUID>()
    public init(){}
    @discardableResult public func begin()->UUID{lock.lock();defer{lock.unlock()};let id=UUID();tickets.insert(id);return id}
    public func end(_ id:UUID){lock.lock();defer{lock.unlock()};tickets.remove(id);cancelled.remove(id)}
    public func cancelAll(){lock.lock();defer{lock.unlock()};cancelled.formUnion(tickets)}
    public func isCancelled(_ id:UUID)->Bool{lock.lock();defer{lock.unlock()};return !tickets.contains(id) || cancelled.contains(id)}
    public var hasWork:Bool{lock.lock();defer{lock.unlock()};return !tickets.isEmpty}
}

@MainActor public final class BackgroundDeliveryGate {
    private let activity:TransferActivity
    private var completions:[UUID:()->Void]=[:]
    private var activated=false
    private var contentPending=true
    public init(activity:TransferActivity){self.activity=activity}
    @discardableResult public func hold(_ completion:@escaping()->Void)->UUID{let id=UUID();completions[id]=completion;return id}
    public func refresh(activated:Bool,contentPending:Bool){
        self.activated=activated;self.contentPending=contentPending
        guard activated,!contentPending,!activity.hasWork else{return}
        let ready=Array(completions.values);completions.removeAll();ready.forEach{$0()}
    }
    public func expire(_ id:UUID){completions.removeValue(forKey:id)?()}
}

public struct WatchPreparationPlan:Codable,Sendable {
    public var mix:RunMix
    public var scheduledIDs:Set<String>=[]
    public init(mix:RunMix){self.mix=mix}
    public func validate()throws{try mix.validate();guard scheduledIDs.isSubset(of:Set(mix.songs.map(\.id))) else{throw CadenceError.message("The saved Watch preparation is invalid.")}}
}
