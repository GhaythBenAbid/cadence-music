import Foundation
import CryptoKit

public struct ListeningEntry:Codable,Identifiable,Sendable {
    public var id:String
    public var song:Song
    public var date:Date
    public var seconds:Double
    public var position:Double
    public var skipped:Bool
    public init(id:String,song:Song,date:Date=Date(),seconds:Double,position:Double,skipped:Bool=false){self.id=id;self.song=song;self.date=date;self.seconds=seconds;self.position=position;self.skipped=skipped}
}
public struct ListeningProfile:Codable,Sendable {
    public var history:[ListeningEntry]=[]
    public var followedArtists:[MusicCatalogEntry]=[]
    public var savedCatalog:[MusicCatalogEntry]=[]
    public init(){}
    public mutating func record(_ event:ListeningEntry){
        guard event.seconds.isFinite,event.seconds>=1,event.position.isFinite else{return}
        if let i=history.firstIndex(where:{$0.id==event.id}){history[i].seconds=max(history[i].seconds,event.seconds);history[i].position=max(0,event.position);history[i].skipped = history[i].skipped || event.skipped}
        else{history.insert(event,at:0)}
        history=Array(history.sorted{$0.date>$1.date}.prefix(200))
    }
    public var recent:[ListeningEntry]{var seen=Set<String>();return history.filter{seen.insert($0.song.id).inserted}}
    public mutating func follow(_ artist:MusicCatalogEntry){guard artist.kind == .artist else{return};if let i=followedArtists.firstIndex(where:{$0.id==artist.id}){followedArtists.remove(at:i)}else{followedArtists.insert(artist,at:0);followedArtists=Array(followedArtists.prefix(100))}}
    public mutating func save(_ entry:MusicCatalogEntry){guard entry.kind == .song else{return};if !savedCatalog.contains(where:{$0.id==entry.id}){savedCatalog.insert(entry,at:0);savedCatalog=Array(savedCatalog.prefix(500))}}
    public mutating func unsave(_ id:String){savedCatalog.removeAll{$0.id==id}}
    public func recommendations(candidates:[Song],favorites:[Song],seed:Song?=nil,day:Date=Date())->[Song]{
        let followed=Set(followedArtists.map{$0.artist.lowercased()}),favArtists=Set(favorites.compactMap{$0.artist?.lowercased()}),favIDs=Set(favorites.map(\.id))
        let recentIDs=Set(history.prefix(20).map{$0.song.id})
        var affinity:[String:Double]=[:],skipCounts:[String:Int]=[:]
        for event in history.prefix(100){let artist=(event.song.artist ?? "").lowercased();affinity[artist,default:0]+=event.skipped ? -2 : min(event.seconds/30,4);if event.skipped{skipCounts[event.song.id,default:0]+=1}}
        let daily=Int(day.timeIntervalSince1970/86400)
        func score(_ song:Song)->Double{
            let artist=(song.artist ?? "").lowercased()
            let digest=SHA256.hash(data:Data((String(daily)+song.id).utf8));let variety=Double(Array(digest).first ?? 0)/256
            return (artist==seed?.artist?.lowercased() ? 20 : 0)+(followed.contains(artist) ? 10 : 0)+(favArtists.contains(artist) ? 6 : 0)+(favIDs.contains(song.id) ? 2 : 0)+min(affinity[artist,default:0],12)-(recentIDs.contains(song.id) ? 10 : 0)-Double(skipCounts[song.id,default:0]*12)+variety
        }
        var seen=Set<String>();let songs=(candidates+favorites).filter{$0.id != seed?.id && seen.insert($0.id).inserted}
        return songs.sorted{let a=score($0),b=score($1);return a==b ? $0.id<$1.id : a>b}
    }
}
public struct ListeningProfileStore:Sendable {
    let root:URL
    public init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceListening",isDirectory:true)}
    private func file(_ account:String)->URL{root.appendingPathComponent(SHA256.hash(data:Data(account.utf8)).map{String(format:"%02x",$0)}.joined()+".json")}
    public func load(_ account:String)->ListeningProfile{guard let data=try? Data(contentsOf:file(account)),data.count<5_000_000 else{return ListeningProfile()};return (try? JSONDecoder().decode(ListeningProfile.self,from:data)) ?? ListeningProfile()}
    public func save(_ value:ListeningProfile,account:String){try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try? JSONEncoder().encode(value).write(to:file(account),options:.atomic)}
    public func clear(_ account:String){try? FileManager.default.removeItem(at:file(account))}
}
