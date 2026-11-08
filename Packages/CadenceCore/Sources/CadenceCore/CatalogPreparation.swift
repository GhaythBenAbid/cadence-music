import Foundation
import CryptoKit

public enum CatalogAction:String,Codable,Sendable {case play,playNext,enqueue,favorite,playlist,download}
public enum PreparationPhase:String,Codable,Sendable {case queued,submitting,preparing,uncertain,ready,applying,complete,blocked,failed,stopped}
public struct CatalogPreparation:Codable,Identifiable,Sendable {
    public var id:String=UUID().uuidString
    public var groupID:String
    public var index:Int
    public var entry:MusicCatalogEntry
    public var action:CatalogAction
    public var playlistID:String?
    public var phase:PreparationPhase = .queued
    public var jobID:String?
    public var song:Song?
    public var message:String="Waiting to prepare"
    public var reviewBeforeApplying=false
    public var createdAt=Date()
    public var checkedAt:Date?
    public init(groupID:String,index:Int,entry:MusicCatalogEntry,action:CatalogAction,playlistID:String?=nil){self.groupID=groupID;self.index=index;self.entry=entry;self.action=action;self.playlistID=playlistID}
    public var active:Bool{[.queued,.submitting,.preparing].contains(phase)}
    public var resolved:Bool{[.ready,.applying,.complete,.blocked,.failed,.stopped].contains(phase)}
}
public struct PreparationArchive:Codable,Sendable {
    public var version=1
    public var items:[CatalogPreparation]
    public init(items:[CatalogPreparation]){self.items=items}
    public func validate()throws{
        guard version==1,items.count<=500,Set(items.map(\.id)).count==items.count,items.allSatisfy({UUID(uuidString:$0.id) != nil && UUID(uuidString:$0.groupID) != nil && $0.entry.kind == .song && $0.index>=0 && $0.index<200 && ($0.action != .playlist || !($0.playlistID ?? "").isEmpty)}) else{throw CadenceError.message("The saved preparation list is invalid.")}
    }
}
public struct PreparationStore:Sendable {
    let root:URL
    public init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadencePreparation",isDirectory:true)}
    private func file(_ account:String)->URL{root.appendingPathComponent(SHA256.hash(data:Data(account.utf8)).map{String(format:"%02x",$0)}.joined()+".json")}
    public func read(_ account:String)throws->[CatalogPreparation]{
        guard FileManager.default.fileExists(atPath:file(account).path) else{return []}
        let data=try Data(contentsOf:file(account));guard data.count<8_000_000 else{throw CadenceError.message("Preparation archive is too large.")}
        let archive=try JSONDecoder().decode(PreparationArchive.self,from:data);try archive.validate();return archive.items
    }
    public func load(_ account:String)->[CatalogPreparation]{(try? read(account)) ?? []}
    public func save(_ items:[CatalogPreparation],account:String)throws{let archive=PreparationArchive(items:items);try archive.validate();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONEncoder().encode(archive).write(to:file(account),options:.atomic)}
    public func clear(_ account:String){try? FileManager.default.removeItem(at:file(account))}
}
