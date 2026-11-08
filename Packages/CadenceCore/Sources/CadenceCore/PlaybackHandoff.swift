import Foundation

public struct PlaybackTransfer:Codable,Sendable {
    public enum Direction:String,Codable,Sendable{case toMac,toPhone,inspect,editQueue}
    public var direction:Direction
    public var snapshot:PlaybackSnapshot?
    public var play:Bool
    public var expectedQueue:[String]?
    public init(_ direction:Direction,snapshot:PlaybackSnapshot?=nil,play:Bool=true,expectedQueue:[String]?=nil){self.direction=direction;self.snapshot=snapshot;self.play=play;self.expectedQueue=expectedQueue}
    public func validate()throws {
        if direction == .toMac || direction == .editQueue{guard let snapshot,!snapshot.queue.entries.isEmpty else{throw CadenceError.message("Choose music before transferring playback.")};try snapshot.validate()}
        if direction == .editQueue{guard let expectedQueue,!expectedQueue.isEmpty,expectedQueue.count<=1000 else{throw CadenceError.message("The queue baseline is missing.")}}
        else if direction != .toMac && snapshot != nil{throw CadenceError.message("Unexpected transfer data.")}
    }
}
public struct TransferredPlayback:Codable,Sendable {
    public var snapshot:PlaybackSnapshot
    public var play:Bool
    public init(snapshot:PlaybackSnapshot,play:Bool){self.snapshot=snapshot;self.play=play}
}
/// Delivered only to an authenticated foreground iPhone that advertises handoff support.
public struct PhoneInstruction:Codable,Sendable,Identifiable {
    public enum Kind:String,Codable,Sendable{case continueOnPhone,continueOnMac,command,enqueue}
    public var id:String
    public var kind:Kind
    public var snapshot:PlaybackSnapshot?
    public var play:Bool
    public var command:PhoneCommand?
    public var song:Song?
    public var playNext:Bool?
    public init(_ kind:Kind,snapshot:PlaybackSnapshot?=nil,play:Bool=true,command:PhoneCommand?=nil,id:String=UUID().uuidString,song:Song?=nil,playNext:Bool?=nil){self.id=id;self.kind=kind;self.snapshot=snapshot;self.play=play;self.command=command;self.song=song;self.playNext=playNext}
    public func validate()throws {
        guard UUID(uuidString:id) != nil else{throw CadenceError.message("Invalid device instruction.")}
        try snapshot?.validate();try command?.validate()
        guard (kind == .enqueue) == (song != nil),(kind == .command) == (command != nil),kind == .continueOnPhone || snapshot==nil else{throw CadenceError.message("Invalid device instruction payload.")}
    }
}
