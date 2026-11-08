import Foundation

/// Catalog metadata is deliberately not a playable Subsonic Song or a preview URL.
public struct MusicCatalogEntry:Codable,Hashable,Identifiable,Sendable {
    public enum Kind:String,Codable,Sendable{case song,artist,album}
    public var id:String
    public var kind:Kind
    public var title:String
    public var artist:String
    public var album:String?
    public var durationMS:Int?
    public var storeURL:String?
    public init(id:String,kind:Kind,title:String,artist:String,album:String?=nil,durationMS:Int?=nil,storeURL:String?=nil){self.id=id;self.kind=kind;self.title=title;self.artist=artist;self.album=album;self.durationMS=durationMS;self.storeURL=storeURL}
    public var link:URL?{guard let storeURL,let url=URL(string:storeURL),url.scheme=="https",let host=url.host,["music.apple.com","itunes.apple.com"].contains(host),url.user==nil,url.password==nil else{return nil};return url}
    public func libraryMatch(_ songs:[Song])->Song?{
        func norm(_ s:String)->String{s.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).trimmingCharacters(in:.whitespacesAndNewlines)}
        let matches=songs.filter{norm($0.title)==norm(title) && norm($0.artist ?? "")==norm(artist)}
        return matches.first{norm($0.album ?? "")==norm(album ?? "")} ?? matches.first
    }
}
public enum GlobalMusicError:Error,LocalizedError {
    case unavailable,permission,uncertain
    public var errorDescription:String?{switch self{
    case .unavailable:return "The music catalog couldn't load. Check your connection and retry."
    case .permission:return "This Aurral account needs permission to add music."
    case .uncertain:return "Aurral didn't confirm the request. It may still be preparing the song. Check again before requesting it another time."
    }}
}
public struct MusicCatalogResponse:Decodable,Sendable {
    private struct Item:Decodable,Sendable {
        var wrapperType:String?;var kind:String?;var artistId:Int?;var collectionId:Int?;var trackId:Int?
        var artistName:String?;var collectionName:String?;var trackName:String?;var trackTimeMillis:Int?
        var artistViewUrl:String?;var collectionViewUrl:String?;var trackViewUrl:String?
    }
    private var results:[Item]
    public func entries(_ kind:MusicCatalogEntry.Kind)->[MusicCatalogEntry]{
        var seen=Set<String>()
        return results.compactMap{item in
            let number:Int?,title:String?,url:String?
            switch kind{
            case .song:guard item.kind=="song" else{return nil};number=item.trackId;title=item.trackName;url=item.trackViewUrl
            case .artist:guard item.wrapperType=="artist" else{return nil};number=item.artistId;title=item.artistName;url=item.artistViewUrl
            case .album:guard item.wrapperType=="collection",item.collectionId != nil else{return nil};number=item.collectionId;title=item.collectionName;url=item.collectionViewUrl
            }
            guard let number,number>0,let title,!title.isEmpty,let artist=item.artistName,!artist.isEmpty else{return nil}
            let id=String(number);guard seen.insert(id).inserted else{return nil}
            return MusicCatalogEntry(id:id,kind:kind,title:title,artist:artist,album:item.collectionName,durationMS:item.trackTimeMillis,storeURL:url)
        }
    }
}
public actor GlobalMusicAPI {
    public static let shared=GlobalMusicAPI()
    private let session:URLSession
    private var cache:[String:[MusicCatalogEntry]]=[:]
    private var lastRequest=Date.distantPast
    public init(session:URLSession = .shared){self.session=session}
    public func search(_ query:String,kind:SearchKind)async throws->[MusicCatalogEntry]{
        let term=query.trimmingCharacters(in:.whitespacesAndNewlines);guard term.count>=2 else{return []}
        let entity=kind == .songs ? "song" : kind == .artists ? "musicArtist" : "album"
        return try await fetch(path:"search",parameters:[.init(name:"term",value:term),.init(name:"entity",value:entity)],kind:kind == .songs ? .song : kind == .artists ? .artist : .album)
    }
    public func children(_ entry:MusicCatalogEntry)async throws->[MusicCatalogEntry]{
        guard entry.kind != .song,Int(entry.id) != nil else{return []}
        return try await fetch(path:"lookup",parameters:[.init(name:"id",value:entry.id),.init(name:"entity",value:entry.kind == .artist ? "album" : "song")],kind:entry.kind == .artist ? .album : .song)
    }
    private func fetch(path:String,parameters:[URLQueryItem],kind:MusicCatalogEntry.Kind)async throws->[MusicCatalogEntry]{
        var parts=URLComponents(string:"https://itunes.apple.com/"+path)!
        parts.queryItems=parameters+[.init(name:"media",value:"music"),.init(name:"country",value:"US"),.init(name:"limit",value:"200")]
        let key=parts.url!.absoluteString
        if let cached=cache[key]{return cached}
        // Recheck after suspending; cancelled typing requests do not reserve future slots.
        while Date().timeIntervalSince(lastRequest)<3.1{try await Task.sleep(for:.seconds(3.1-Date().timeIntervalSince(lastRequest)))}
        try Task.checkCancellation();lastRequest=Date()
        var request=URLRequest(url:parts.url!);request.timeoutInterval=25
        let(data,response)=try await session.data(for:request);try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode==200,data.count<4_000_000 else{throw GlobalMusicError.unavailable}
        let entries=try JSONDecoder().decode(MusicCatalogResponse.self,from:data).entries(kind)
        if cache.count>=12{cache.removeAll()};cache[key]=entries;return entries
    }
}
public struct TrackPreparationReceipt:Decodable,Sendable {
    public var success:Bool
    public var jobId:String?
    public var alreadyOwned:Bool?
    public var queued:Bool?
}
public struct TrackPreparationJob:Decodable,Sendable {
    public var id:String
    public var status:String
    public var progress:Double?
    public var artistName:String?
    public var trackName:String?
    public func matches(_ entry:MusicCatalogEntry)->Bool{trackName?.localizedCaseInsensitiveCompare(entry.title) == .orderedSame && artistName?.localizedCaseInsensitiveCompare(entry.artist) == .orderedSame}
    public init(id:String,status:String,progress:Double?=nil){self.id=id;self.status=status;self.progress=progress}
    public var terminal:Bool{["failed","blocked","cancelled","canceled"].contains(status)}
    public var message:String{switch status{case "pending","queued":return "Queued in Aurral…";case "searching":return "Finding an available source…";case "downloading":return "Preparing audio…";case "processing":return "Processing audio…";case "done":return "Audio ready. Updating the library…";case "blocked":return "Aurral needs a source review. Open Aurral for details.";case "failed":return "Aurral couldn't prepare this song. Try another result or review it in Aurral.";case "cancelled","canceled":return "Preparation was cancelled in Aurral.";default:return "Preparing in Aurral…"}}
}
