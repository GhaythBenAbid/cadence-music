import Foundation
import CryptoKit

public struct CatalogSnapshot:Codable,Sendable {
    public var albums:[Album]
    public var playlists:[Playlist]
    public var favorites:[Song]
    public var discovery:[Song]
    public var playlistRole:Bool?
    public init(albums:[Album],playlists:[Playlist],favorites:[Song],discovery:[Song]=[],playlistRole:Bool?=nil){self.albums=albums;self.playlists=playlists;self.favorites=favorites;self.discovery=discovery;self.playlistRole=playlistRole}
}
public struct CatalogCache:Sendable {
    let root:URL
    public init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceCatalog",isDirectory:true)}
    private func url(_ account:String)->URL{root.appendingPathComponent(SHA256.hash(data:Data(account.utf8)).map{String(format:"%02x",$0)}.joined()+".json")}
    public func load(account:String)->CatalogSnapshot?{(try? Data(contentsOf:url(account))).flatMap{try? JSONDecoder().decode(CatalogSnapshot.self,from:$0)}}
    public func save(_ value:CatalogSnapshot,account:String){try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try? JSONEncoder().encode(value).write(to:url(account),options:.atomic)}
    public func clear(account:String){try? FileManager.default.removeItem(at:url(account))}
}
public enum LibraryDiscovery {
    public static func mix(random:[Song],favorites:[Song],seed:Song?=nil)->[Song]{
        let artists=Set((favorites+[seed].compactMap{$0}).compactMap{$0.artist?.lowercased()})
        let favoriteIDs=Set(favorites.map(\.id))
        let related=random.filter{artists.contains(($0.artist ?? "").lowercased()) && !favoriteIDs.contains($0.id)}
        var seen=Set<String>();return (related+random+favorites).filter{song in guard song.id != seed?.id else{return false};return seen.insert(song.id).inserted}
    }
}
