import Foundation
import CryptoKit

public struct DiscoverArtist:Codable,Identifiable,Hashable,Sendable {
    public var id:String{mbid ?? name.lowercased()}
    public var mbid:String?
    public var name:String
    public var image:String?
    public var tags:[String]
    public var sourceArtists:[String]
    public var sourceArtist:String?
    public var popularityLabel:String?
    public init(mbid:String?=nil,name:String,image:String?=nil,tags:[String]=[],sourceArtists:[String]=[],sourceArtist:String?=nil,popularityLabel:String?=nil){self.mbid=mbid;self.name=name;self.image=image;self.tags=tags;self.sourceArtists=sourceArtists;self.sourceArtist=sourceArtist;self.popularityLabel=popularityLabel}
    enum CodingKeys:String,CodingKey{case mbid="id",name,image,tags,sourceArtists,sourceArtist,popularityLabel}
    public init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);mbid=try c.decodeIfPresent(String.self,forKey:.mbid);name=try c.decode(String.self,forKey:.name);image=try c.decodeIfPresent(String.self,forKey:.image);tags=try c.decodeIfPresent([String].self,forKey:.tags) ?? [];sourceArtists=try c.decodeIfPresent([String].self,forKey:.sourceArtists) ?? [];sourceArtist=try c.decodeIfPresent(String.self,forKey:.sourceArtist);popularityLabel=try c.decodeIfPresent(String.self,forKey:.popularityLabel)}
    public var reason:String{let seeds=sourceArtists.prefix(2).joined(separator:" & ");return !seeds.isEmpty ? "Because you like "+seeds : (sourceArtist.map{"Because you like "+$0} ?? popularityLabel ?? "A new artist to explore")}
}
public struct DiscoverResponse:Codable,Sendable {
    public var recommendations:[DiscoverArtist]
    public var globalTop:[DiscoverArtist]
    public var configured:Bool?
    public var provider:String?
    public var lastUpdated:String?
    public init(recommendations:[DiscoverArtist]=[],globalTop:[DiscoverArtist]=[],configured:Bool?=nil,provider:String?=nil,lastUpdated:String?=nil){self.recommendations=recommendations;self.globalTop=globalTop;self.configured=configured;self.provider=provider;self.lastUpdated=lastUpdated}
}
public struct DiscoverRelease:Codable,Identifiable,Hashable,Sendable {
    public var id:String
    public var albumName:String
    public var artistName:String
    public var artistMbid:String?
    public var releaseDate:String?
    public var albumType:String?
    public var coverUrl:String?
    public init(id:String,albumName:String,artistName:String,artistMbid:String?=nil,releaseDate:String?=nil,albumType:String?=nil,coverUrl:String?=nil){self.id=id;self.albumName=albumName;self.artistName=artistName;self.artistMbid=artistMbid;self.releaseDate=releaseDate;self.albumType=albumType;self.coverUrl=coverUrl}
    public var date:Date?{guard let text=releaseDate,text.count==10 else{return nil};let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0);f.dateFormat="yyyy-MM-dd";f.isLenient=false;guard let date=f.date(from:text),f.string(from:date)==text else{return nil};return date}
    public func upcoming(now:Date=Date())->Bool{var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!;return date.map{$0>calendar.startOfDay(for:now)} ?? false}
}
public struct DiscoverPlaylist:Codable,Identifiable,Hashable,Sendable {
    public var id:String
    public var name:String
    public var trackCount:Int?
    public var artworkUrl:String?
    public var curator:String?
    public init(id:String,name:String,trackCount:Int?=nil,artworkUrl:String?=nil,curator:String?=nil){self.id=id;self.name=name;self.trackCount=trackCount;self.artworkUrl=artworkUrl;self.curator=curator}
}
public struct DiscoverTrack:Codable,Identifiable,Hashable,Sendable {
    public var id:String
    public var title:String
    public var artistName:String?
    public var album:String?
    public var artworkUrl:String?
    public var previewURL:String?
    public var durationMS:Int?
    public init(id:String,title:String,artistName:String?=nil,album:String?=nil,artworkUrl:String?=nil,previewURL:String?=nil,durationMS:Int?=nil){self.id=id;self.title=title;self.artistName=artistName;self.album=album;self.artworkUrl=artworkUrl;self.previewURL=previewURL;self.durationMS=durationMS}
    enum CodingKeys:String,CodingKey{case id,title,artistName,album,artworkUrl;case previewURL="preview_url",durationMS="duration_ms"}
    private enum AlternateKeys:String,CodingKey{case trackName,albumName,durationMs}
    public init(from decoder:Decoder)throws{
        let c=try decoder.container(keyedBy:CodingKeys.self),a=try decoder.container(keyedBy:AlternateKeys.self)
        title=try c.decodeIfPresent(String.self,forKey:.title) ?? a.decode(String.self,forKey:.trackName)
        artistName=try c.decodeIfPresent(String.self,forKey:.artistName);album=try c.decodeIfPresent(String.self,forKey:.album) ?? a.decodeIfPresent(String.self,forKey:.albumName)
        artworkUrl=try c.decodeIfPresent(String.self,forKey:.artworkUrl);previewURL=try c.decodeIfPresent(String.self,forKey:.previewURL)
        durationMS=try c.decodeIfPresent(Int.self,forKey:.durationMS) ?? a.decodeIfPresent(Int.self,forKey:.durationMs)
        id=(try? c.decode(String.self,forKey:.id)) ?? SHA256.hash(data:Data((title+"|"+(artistName ?? "")+"|"+(album ?? "")).utf8)).map{String(format:"%02x",$0)}.joined()
    }
}
public struct DiscoverPlaylistDetail:Decodable,Sendable {public var tracks:[DiscoverTrack]}
public struct DiscoverSnapshot:Codable,Sendable {
    public var response:DiscoverResponse
    public var releases:[DiscoverRelease]
    public var playlists:[DiscoverPlaylist]
    public var savedAt:Date
    public var partialSources:[String]?
    public var seenReleaseIDs:Set<String>
    public init(response:DiscoverResponse,releases:[DiscoverRelease],playlists:[DiscoverPlaylist]=[],savedAt:Date=Date(),seenReleaseIDs:Set<String>=[]){self.response=response;self.releases=releases;self.playlists=playlists;self.savedAt=savedAt;self.seenReleaseIDs=seenReleaseIDs}
    public var newCount:Int{releases.filter{!seenReleaseIDs.contains($0.id)}.count}
}
public enum DiscoveryLinks {
    public static func media(_ value:String?,server:URL)->URL?{guard let value,!value.isEmpty,let url=URL(string:value,relativeTo:server)?.absoluteURL,url.scheme=="https",url.host != nil,url.user==nil,url.password==nil else{return nil};return url}
    public static func artist(_ artist:DiscoverArtist,server:URL)->URL{if let id=artist.mbid,UUID(uuidString:id) != nil{return server.appendingPathComponent("artist").appendingPathComponent(id)};var parts=URLComponents(url:server.appendingPathComponent("search"),resolvingAgainstBaseURL:false)!;parts.queryItems=[URLQueryItem(name:"q",value:artist.name)];return parts.url!}
    public static func release(_ release:DiscoverRelease,server:URL)->URL?{guard let artist=release.artistMbid,UUID(uuidString:artist) != nil,UUID(uuidString:release.id) != nil else{return nil};return server.appendingPathComponent("artist").appendingPathComponent(artist).appendingPathComponent("release").appendingPathComponent(release.id)}
    public static func libraryMatch(_ track:DiscoverTrack,artist:String,songs:[Song])->Song?{func normalized(_ value:String)->String{value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).trimmingCharacters(in:.whitespacesAndNewlines)};return songs.first{normalized($0.title)==normalized(track.title) && normalized($0.artist ?? "")==normalized(track.artistName ?? artist)}}
}
public protocol DiscoverySessionVault:Sendable {func load(_ key:String)->Data?;func save(_ data:Data?,key:String)}
public enum DiscoveryAPIError:Error,LocalizedError {case unauthenticated,unavailable,permission,unsupported
    public var errorDescription:String?{switch self{case .unauthenticated:return "Sign in again to load Discover.";case .permission:return "This Aurral account does not have access to discovery.";case .unsupported:return "This Aurral server does not support Discover yet.";case .unavailable:return "Discover couldn't reach Aurral. Check your server connection and try again."}}
}
public actor AurralDiscoveryAPI {
    public struct Session:Codable,Sendable {public var token:String;public var expiresAt:Double}
    private let credentials:ServerCredentials
    private let session:URLSession
    private let vault:(any DiscoverySessionVault)?
    private let key:String
    private var token:Session?
    private var authenticating:Task<Session,Error>?
    private var generation=UUID()
    private var signedOut=false
    public init(credentials:ServerCredentials,session:URLSession = .shared,vault:(any DiscoverySessionVault)?=nil){self.credentials=credentials;self.session=session;self.vault=vault;key=SHA256.hash(data:Data((credentials.accountKey+"|"+credentials.password).utf8)).map{String(format:"%02x",$0)}.joined()}
    private func raw(_ path:[String],query:[URLQueryItem]=[],body:Data?=nil,bearer:String?=nil,timeout:TimeInterval=35)async throws->(Data,Int){
        var endpoint=credentials.server;for part in ["api"]+path{endpoint.appendPathComponent(part)}
        var parts=URLComponents(url:endpoint,resolvingAgainstBaseURL:false)!;if !query.isEmpty{parts.queryItems=query}
        var request=URLRequest(url:parts.url!);request.httpMethod=body==nil ? "GET" : "POST";request.httpBody=body;request.timeoutInterval=timeout;request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json",forHTTPHeaderField:"Content-Type");if let bearer{request.setValue("Bearer "+bearer,forHTTPHeaderField:"Authorization")}
        let (data,response)=try await session.data(for:request);guard let response=response as? HTTPURLResponse,data.count<12_000_000 else{throw DiscoveryAPIError.unavailable};return(data,response.statusCode)
    }
    private func credentialToken()async throws->Session{
        guard !signedOut else{throw CancellationError()}
        if token==nil,let data=vault?.load(key){token=try? JSONDecoder().decode(Session.self,from:data)}
        if let token,token.expiresAt/1000>Date().timeIntervalSince1970+60{return token}
        if let authenticating{return try await authenticating.value}
        let stamp=generation
        let work=Task{() async throws->Session in
            let body=try JSONEncoder().encode(["username":credentials.username,"password":credentials.password])
            let (data,status)=try await raw(["auth","login"],body:body)
            guard status==200 else{throw status==403 ? DiscoveryAPIError.permission : DiscoveryAPIError.unauthenticated}
            let value=try JSONDecoder().decode(Session.self,from:data);guard !value.token.isEmpty,value.expiresAt>Date().timeIntervalSince1970*1000 else{throw DiscoveryAPIError.unauthenticated};return value
        };authenticating=work
        do{let value=try await work.value;guard generation==stamp,!signedOut else{_=try? await raw(["auth","logout"],body:Data("{}".utf8),bearer:value.token);throw CancellationError()};authenticating=nil;token=value;vault?.save(try JSONEncoder().encode(value),key:key);return value}catch{authenticating=nil;throw error}
    }
    private func get<T:Decodable & Sendable>(_ path:[String],query:[URLQueryItem]=[])async throws->T{
        for attempt in 0...1{
            let auth=try await credentialToken();let (data,status)=try await raw(path,query:query,bearer:auth.token)
            if status==401 && attempt==0{if token?.token==auth.token{token=nil;vault?.save(nil,key:key)};continue}
            guard (200..<300).contains(status) else{throw status==403 ? DiscoveryAPIError.permission : status==401 ? DiscoveryAPIError.unauthenticated : DiscoveryAPIError.unavailable}
            return try JSONDecoder().decode(T.self,from:data)
        };throw DiscoveryAPIError.unauthenticated
    }
    public func feed()async throws->DiscoverSnapshot{
        struct Bootstrap:Decodable{struct Contract:Decodable{var version:Int;var features:[String]};var api:Contract?}
        let (data,status)=try await raw(["health","bootstrap"]);guard status==200 else{throw status==404 ? DiscoveryAPIError.unsupported : DiscoveryAPIError.unavailable}
        let bootstrap=try JSONDecoder().decode(Bootstrap.self,from:data);guard bootstrap.api?.version==1,bootstrap.api?.features.contains("discover")==true else{throw DiscoveryAPIError.unsupported}
        struct Shelf:Decodable,Sendable{var forYou:[DiscoverPlaylist]}
        async let recent:[DiscoverRelease]?=try? get(["library","recent-releases"])
        async let editorial:Shelf?=try? get(["discover","editorial"])
        let response:DiscoverResponse=try await get(["discover"],query:[.init(name:"limit",value:"40")])
        let (releases,shelf)=await(recent,editorial)
        var result=DiscoverSnapshot(response:response,releases:releases ?? [],playlists:shelf?.forYou ?? [])
        result.partialSources=(releases==nil ? ["releases"] : [])+(shelf==nil ? ["playlists"] : [])
        return result
    }

    public func artistTracks(_ artist:DiscoverArtist)async throws->[DiscoverTrack]{guard let id=artist.mbid,UUID(uuidString:id) != nil else{return []};struct Response:Decodable,Sendable{var tracks:[DiscoverTrack]};let value:Response=try await get(["artists",id,"preview"],query:[.init(name:"artistName",value:artist.name)]);return value.tracks}
    public func playlist(_ playlist:DiscoverPlaylist)async throws->DiscoverPlaylistDetail{guard !playlist.id.isEmpty,playlist.id.allSatisfy(\.isNumber) else{throw DiscoveryAPIError.unavailable};return try await get(["discover","editorial",playlist.id])}
    public func spotifyConnection()async throws->SpotifyConnection {
        do{return try await get(["playlists","import","spotify","status"])}
        catch DiscoveryAPIError.permission{throw SpotifyImportError.permission}
        catch{throw SpotifyImportError.unavailable}
    }
    public func importStatus()async throws->PlaylistImportStatus {
        do{return try await get(["playlists","status"])}
        catch DiscoveryAPIError.permission{throw SpotifyImportError.permission}
        catch{throw SpotifyImportError.unavailable}
    }
    private struct SpotifyFailure:Decodable{var code:String?;var error:String?}
    // A mutation is never retried automatically: a lost response can still mean an accepted import.
    private func spotifyPost<T:Decodable & Sendable>(_ suffix:[String]=[],body:Data,mutation:Bool=false)async throws->T {
        let auth=try await credentialToken()
        let result:(Data,Int)
        do{result=try await raw(["playlists","import","spotify"]+suffix,body:body,bearer:auth.token,timeout:120)}
        catch{throw mutation ? SpotifyImportError.uncertain : SpotifyImportError.unavailable}
        let (data,status)=result
        if status==401 {
            if (try? JSONDecoder().decode(SpotifyFailure.self,from:data))?.code=="SPOTIFY_AUTH_REQUIRED"{throw SpotifyImportError.connect}
            token=nil;vault?.save(nil,key:key);throw SpotifyImportError.session
        }
        if status==403{let failure=try? JSONDecoder().decode(SpotifyFailure.self,from:data);throw failure?.error=="Forbidden" ? SpotifyImportError.permission : SpotifyImportError.playlistAccess}
        if status==409{throw SpotifyImportError.conflict}
        guard (200..<300).contains(status) else{throw mutation && status>=500 ? SpotifyImportError.uncertain : SpotifyImportError.unavailable}
        do{return try JSONDecoder().decode(T.self,from:data)}catch{throw mutation ? SpotifyImportError.uncertain : SpotifyImportError.unavailable}
    }
    public func previewSpotify(link:String)async throws->SpotifyImportPreview {
        guard let id=SpotifyPlaylistLink.id(link) else{throw SpotifyImportError.invalidLink}
        return try await spotifyPost(["preview"],body:JSONEncoder().encode(["playlistId":id]))
    }
    public func importSpotify(link:String,name:String,sync:Bool)async throws->SpotifyImportReceipt {
        guard let id=SpotifyPlaylistLink.id(link) else{throw SpotifyImportError.invalidLink}
        struct Request:Encodable{var playlistId:String;var name:String;var syncEnabled:Bool;var syncIntervalHours:Int;var keepRemovedTracks:Bool}
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty else{throw SpotifyImportError.unavailable}
        return try await spotifyPost(body:JSONEncoder().encode(Request(playlistId:id,name:title,syncEnabled:sync,syncIntervalHours:sync ? 24 : 0,keepRemovedTracks:true)),mutation:true)
    }
    public func prepareTrack(_ track:MusicCatalogEntry)async throws->TrackPreparationReceipt {
        guard track.kind == .song,!track.title.isEmpty,!track.artist.isEmpty else{throw GlobalMusicError.unavailable}
        struct Body:Encodable{var artistName:String;var trackName:String;var albumName:String?;var durationMs:Int?}
        let auth=try await credentialToken(),body=try JSONEncoder().encode(Body(artistName:track.artist,trackName:track.title,albumName:track.album,durationMs:track.durationMS))
        let result:(Data,Int)
        do{result=try await raw(["library","downloads","track"],body:body,bearer:auth.token,timeout:45)}catch{throw GlobalMusicError.uncertain}
        if result.1==403{throw GlobalMusicError.permission}
        guard (200..<300).contains(result.1) else{throw result.1>=500 ? GlobalMusicError.uncertain : GlobalMusicError.unavailable}
        guard let value=try? JSONDecoder().decode(TrackPreparationReceipt.self,from:result.0),value.success else{throw GlobalMusicError.uncertain};return value
    }
    public func preparationJobs()async throws->[TrackPreparationJob]{try await get(["playlists","jobs"])}
    public func signOut()async{signedOut=true;generation=UUID();let current=token ?? vault?.load(key).flatMap{try? JSONDecoder().decode(Session.self,from:$0)};token=nil;authenticating?.cancel();authenticating=nil;vault?.save(nil,key:key);if let current{_=try? await raw(["auth","logout"],body:Data("{}".utf8),bearer:current.token)}}
}
