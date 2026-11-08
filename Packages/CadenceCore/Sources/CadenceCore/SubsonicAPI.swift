import Foundation
import CryptoKit

public struct SubsonicAPI: Sendable {
    public let credentials: ServerCredentials
    public let session: URLSession
    public init(credentials: ServerCredentials, session: URLSession = .shared) { self.credentials=credentials; self.session=session }
    public func authentication(salt: String = UUID().uuidString) -> [URLQueryItem] {
        let token = Insecure.MD5.hash(data: Data((credentials.password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        return [.init(name:"u",value:credentials.username), .init(name:"t",value:token), .init(name:"s",value:salt), .init(name:"v",value:"1.16.1"), .init(name:"c",value:"Cadence"), .init(name:"f",value:"json")]
    }
    public func endpoint(_ method: String) -> URL { credentials.server.appendingPathComponent("rest").appendingPathComponent(method + ".view") }
    public func request(_ method: String, parameters: [URLQueryItem] = []) -> URLRequest {
        var request = URLRequest(url: endpoint(method)); request.httpMethod="POST"; request.timeoutInterval=35
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField:"Content-Type")
        var parts = URLComponents(); parts.queryItems = authentication() + parameters
        request.httpBody = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using:.utf8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
    public func authenticatedURL(_ method: String, parameters: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: endpoint(method), resolvingAgainstBaseURL:false)!
        parts.queryItems=authentication()+parameters
        return parts.url!
    }
    public func call(_ method: String, parameters: [URLQueryItem] = []) async throws -> SubsonicResponse {
        let (data,response) = try await session.data(for: request(method, parameters:parameters))
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CadenceError.message("The server isn't responding. Check your server connection and try again.") }
        do { return try JSONDecoder().decode(SubsonicEnvelope.self, from:data).response.checked() }
        catch let error as CadenceError { throw error }
        catch { throw CadenceError.message("The server returned an unexpected response.") }
    }
    public func ping() async throws { _ = try await call("ping") }
    public func albums(offset:Int=0,size:Int=100) async throws -> [Album] { try await call("getAlbumList2", parameters:[.init(name:"type",value:"newest"), .init(name:"size",value:String(max(1,min(size,100)))),.init(name:"offset",value:String(max(0,offset)))]).albumList2?.album ?? [] }
    public func album(_ id: String) async throws -> Album { guard let album = try await call("getAlbum", parameters:[.init(name:"id",value:id)]).album else { throw CadenceError.message("This album isn't available.") }; return album }
    public func playlists() async throws -> [Playlist] { try await call("getPlaylists").playlists?.playlist ?? [] }
    public func playlist(_ id: String) async throws -> Playlist { guard let playlist = try await call("getPlaylist", parameters:[.init(name:"id",value:id)]).playlist else { throw CadenceError.message("This playlist isn't available.") }; return playlist }
    public func search(_ query: String) async throws -> SearchResults { try await call("search3", parameters:[.init(name:"query",value:query), .init(name:"songCount",value:"100"), .init(name:"albumCount",value:"30")]).searchResult3 ?? SearchResults() }
    public func search(_ query:String,kind:SearchKind,offset:Int=0,size:Int=30)async throws->SearchResults {
        try await call("search3",parameters:[.init(name:"query",value:query)]+kind.parameters(offset:offset,size:size)).searchResult3 ?? SearchResults()
    }
    public func artist(_ id:String)async throws->Artist {
        guard let value=try await call("getArtist",parameters:[.init(name:"id",value:id)]).artist else{throw CadenceError.message("This artist isn't available.")};return value
    }
    public func favorites() async throws -> [Song] { try await call("getStarred2").starred2?.song ?? [] }
    public func favorite(_ song: Song, enabled: Bool) async throws { _ = try await call(enabled ? "star" : "unstar", parameters:[.init(name:"id",value:song.id)]) }
    @discardableResult public func createPlaylist(name:String,songs:[Song])async throws->Playlist?{try await call("createPlaylist",parameters:[.init(name:"name",value:name)]+songs.map{.init(name:"songId",value:$0.id)}).playlist}
    public func playlistPermission()async throws->Bool?{try await call("getUser",parameters:[.init(name:"username",value:credentials.username)]).user?.playlistRole}
    public func randomSongs(count:Int=30)async throws->[Song]{try await call("getRandomSongs",parameters:[.init(name:"size",value:String(max(1,min(count,100))))]).randomSongs?.song ?? []}
    public func relatedSongs(to song:Song)async throws->[Song]{
        guard let artist=song.artist,!artist.isEmpty else{return try await randomSongs()}
        let matching=try await search(artist).song ?? []
        let random=(try? await randomSongs()) ?? []
        return LibraryDiscovery.mix(random:matching+random,favorites:[],seed:song)
    }
    public func editPlaylist(_ playlist:Playlist,name:String,songs:[Song])async throws {
        let latest=try await self.playlist(playlist.id)
        guard latest.name==playlist.name,(latest.entry ?? []).map(\.id)==(playlist.entry ?? []).map(\.id) else{throw CadenceError.message("This playlist changed on another device. Reopen the editor before saving.")}
        let removals=(0..<(latest.entry ?? []).count).reversed().map{URLQueryItem(name:"songIndexToRemove",value:String($0))}
        _=try await call("updatePlaylist",parameters:[.init(name:"playlistId",value:playlist.id),.init(name:"name",value:name)]+removals+songs.map{.init(name:"songIdToAdd",value:$0.id)})
    }
    public func deletePlaylist(_ id:String)async throws{_=try await call("deletePlaylist",parameters:[.init(name:"id",value:id)])}
    public func artwork(_ id: String) async throws -> Data {
        let (data,response) = try await session.data(for:request("getCoverArt", parameters:[.init(name:"id",value:id), .init(name:"size",value:"480")]))
        guard let http=response as? HTTPURLResponse, http.statusCode==200, (http.mimeType ?? "").hasPrefix("image/"), data.count <= 8_000_000 else { throw CadenceError.message("Artwork unavailable.") }
        return data
    }
    public func download(_ song: Song) async throws -> URL {
        let (url,response) = try await session.download(for:request("download", parameters:[.init(name:"id",value:song.id)]))
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode), (http.mimeType ?? "").hasPrefix("audio/") || http.mimeType == "application/octet-stream" else { try? FileManager.default.removeItem(at:url); throw CadenceError.message("This track couldn't be downloaded. Check your connection and try again.") }
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 300_000_000 else { try? FileManager.default.removeItem(at:url); throw CadenceError.message("This track is empty or too large for a Watch mix.") }
        return url
    }
}
