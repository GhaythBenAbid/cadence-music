import Foundation
import CryptoKit

public enum RepeatMode:String,Codable,CaseIterable,Sendable {case off,all,one
    public var next:Self{switch self{case .off:return .all;case .all:return .one;case .one:return .off}}
    public var label:String{switch self{case .off:return "Repeat off";case .all:return "Repeat all";case .one:return "Repeat one"}}
}
public struct QueueEntry:Codable,Identifiable,Equatable,Sendable {
    public var id:String
    public var song:Song
    public init(song:Song,id:String=UUID().uuidString){self.song=song;self.id=id}
}
public struct PlaybackQueue:Codable,Equatable,Sendable {
    public private(set) var entries:[QueueEntry]=[]
    public private(set) var index=0
    public private(set) var shuffled=false
    private var baseline:[QueueEntry]=[]
    public init(){}
    public init(songs:[Song],startingAt song:Song?=nil){entries=Array(songs.prefix(1000)).map{QueueEntry(song:$0)};baseline=entries;index=song.flatMap{selected in entries.firstIndex{$0.song.id==selected.id}} ?? 0}
    public var current:QueueEntry?{entries.indices.contains(index) ? entries[index] : nil}
    public var upcoming:[QueueEntry]{Array(entries.dropFirst(min(entries.count,index+1)))}
    public func validate()throws{
        guard entries.count<=1000,baseline.count==entries.count,Set(baseline.map(\.id)).count==baseline.count,Set(entries.map(\.id)).count==entries.count,entries.allSatisfy({UUID(uuidString:$0.id) != nil}),Set(entries.map(\.id))==Set(baseline.map(\.id)),(entries.isEmpty ? index==0 : entries.indices.contains(index)) else{throw CadenceError.message("The saved queue is invalid.")}
    }
    public mutating func append(_ song:Song,next:Bool=false){
        guard entries.count<1000 else{return};let entry=QueueEntry(song:song)
        let position=next && !entries.isEmpty ? index+1 : entries.count
        entries.insert(entry,at:position)
        if next,let current,let original=baseline.firstIndex(where:{$0.id==current.id}){baseline.insert(entry,at:original+1)}else{baseline.append(entry)}
    }
    public mutating func removeUpcoming(_ id:String){guard let position=entries.firstIndex(where:{$0.id==id}),position>index else{return};entries.remove(at:position);baseline.removeAll{$0.id==id}}
    public mutating func moveUpcoming(from source:Int,to destination:Int){
        var future=upcoming;guard future.indices.contains(source),destination>=0,destination<=future.count else{return}
        let item=future.remove(at:source);future.insert(item,at:min(destination,future.count));entries=Array(entries.prefix(index+1))+future;baseline=entries
    }
    public mutating func clearUpcoming(){let keep=Set(entries.prefix(index+1).map(\.id));entries=Array(entries.prefix(index+1));baseline.removeAll{!keep.contains($0.id)}}
    public mutating func jump(to id:String)->Bool{guard let next=entries.firstIndex(where:{$0.id==id}) else{return false};index=next;return true}
    public mutating func advance(repeating:Bool)->Bool{guard !entries.isEmpty else{return false};if index+1<entries.count{index+=1;return true};if repeating{index=0;return true};return false}
    public mutating func trimHistory(keeping count:Int){
        let remove=max(0,index-max(0,count));guard remove>0 else{return}
        entries.removeFirst(remove);index-=remove;let ids=Set(entries.map(\.id));baseline.removeAll{!ids.contains($0.id)}
    }
    public mutating func previous(){index=max(0,index-1)}
    public mutating func toggleShuffle(){
        guard current != nil else{return};shuffled.toggle()
        let played=Array(entries.prefix(index+1)),playedIDs=Set(played.map(\.id))
        entries=played+(shuffled ? upcoming.shuffled() : baseline.filter{!playedIDs.contains($0.id)})
    }
}
public struct PlaybackSnapshot:Codable,Sendable {
    public var version=1
    public var queue:PlaybackQueue
    public var position:Double
    public var repeats:Bool
    public var volume:Float
    public var repeatMode:RepeatMode?
    public var autoplay:Bool?
    public var savedAt:Date
    public init(queue:PlaybackQueue,position:Double,repeats:Bool,volume:Float,savedAt:Date=Date(),repeatMode:RepeatMode?=nil,autoplay:Bool?=nil){self.queue=queue;self.position=position;self.repeats=repeats;self.volume=volume;self.savedAt=savedAt;self.repeatMode=repeatMode;self.autoplay=autoplay}
    public func validate()throws{try queue.validate();guard version==1,position.isFinite,position>=0,position<=31_536_000,volume.isFinite,(0...1).contains(volume) else{throw CadenceError.message("The saved playback position is invalid.")}}
}
public struct PlaybackSessionStore:Sendable {
    public let root:URL
    public init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadencePlayback",isDirectory:true)}
    private func url(_ account:String)->URL{root.appendingPathComponent(SHA256.hash(data:Data(account.utf8)).map{String(format:"%02x",$0)}.joined()+".json")}
    public func save(_ snapshot:PlaybackSnapshot,account:String)throws{try snapshot.validate();guard !account.isEmpty else{return};try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONEncoder().encode(snapshot).write(to:url(account),options:.atomic)}
    public func load(account:String)->PlaybackSnapshot?{guard let data=try? Data(contentsOf:url(account)),let value=try? JSONDecoder().decode(PlaybackSnapshot.self,from:data),(try? value.validate()) != nil else{return nil};return value}
    public func clear(account:String){try? FileManager.default.removeItem(at:url(account))}
}
