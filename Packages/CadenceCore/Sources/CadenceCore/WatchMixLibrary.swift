import Foundation

public struct WatchSavedMix:Codable,Identifiable,Sendable {
    public var id:String
    public var name:String
    public var songCount:Int
    public var readyIDs:[String]
    public init(mix:RunMix,readyIDs:[String]){id=mix.id;name=mix.name;songCount=mix.songs.count;self.readyIDs=readyIDs}
}
public struct WatchMixLibraryReceipt:Codable,Sendable {
    public var version=2
    public var accountKey:String?
    public var mixes:[WatchSavedMix]
    public var updatedAt=Date()
    public init(accountKey:String?,mixes:[WatchSavedMix]){self.accountKey=accountKey;self.mixes=mixes}
    public func validate()throws{
        guard version==2,mixes.count<=10,Set(mixes.map(\.id)).count==mixes.count,mixes.allSatisfy({!$0.id.isEmpty && $0.songCount<=100 && Set($0.readyIDs).count<=$0.songCount}),mixes.isEmpty || accountKey != nil else{throw CadenceError.message("Invalid Watch library receipt.")}
    }
}
public struct WatchMixRemoval:Codable,Sendable {
    public var id:String
    public var accountKey:String
    public var createdAt:Date
    public var removedAt:Date
    public init(_ mix:RunMix,removedAt:Date=Date()){id=mix.id;accountKey=mix.accountKey;createdAt=mix.createdAt;self.removedAt=removedAt}
}
