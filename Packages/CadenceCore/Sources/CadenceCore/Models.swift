import Foundation
import CryptoKit

public struct ServerCredentials: Codable, Equatable, Sendable {
    public let server: URL
    public let username: String
    public let password: String
    public init(server: URL, username: String, password: String) {
        self.server = server; self.username = username.trimmingCharacters(in: .whitespacesAndNewlines); self.password = password
    }
    public var accountKey: String { SHA256.hash(data: Data((server.absoluteString.lowercased() + "|" + username.lowercased()).utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func normalizedServer(_ text: String) throws -> URL {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), parts.scheme?.lowercased() == "https", parts.host != nil, parts.user == nil, parts.password == nil else { throw CadenceError.message("Enter an HTTPS server address, without credentials.") }
        parts.query = nil; parts.fragment = nil
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "rest" { path = "" }
        parts.path = path.isEmpty ? "" : "/" + path
        guard let url = parts.url else { throw CadenceError.message("That server address is not valid.") }
        return url
    }
}

public enum CadenceError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

public struct Song: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var artist: String?
    public var album: String?
    public var albumId: String?
    public var coverArt: String?
    public var duration: Int?
    public var contentType: String?
    public var starred: String?
    public init(id: String, title: String, artist: String? = nil, album: String? = nil, albumId: String? = nil, coverArt: String? = nil, duration: Int? = nil, contentType: String? = nil, starred: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.albumId = albumId; self.coverArt = coverArt; self.duration = duration; self.contentType = contentType; self.starred = starred
    }
    public var subtitle: String { artist ?? "Unknown artist" }
    public var audioExtension: String {
        switch contentType?.lowercased().split(separator:";").first.map(String.init) {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/aac": return "aac"
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/ogg", "application/ogg": return "ogg"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        default: return "m4a"
        }
    }
    public var filename: String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() + "." + audioExtension }
    public var durationLabel: String { let seconds = duration ?? 0; return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
public struct Album: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var artist: String?
    public var coverArt: String?
    public var songCount: Int?
    public var year: Int?
    public var song: [Song]?
    public init(id: String, name: String, artist: String? = nil, coverArt: String? = nil, songCount: Int? = nil, year: Int? = nil, song: [Song]? = nil) {
        self.id=id; self.name=name; self.artist=artist; self.coverArt=coverArt; self.songCount=songCount; self.year=year; self.song=song
    }
}
public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var songCount: Int?
    public var duration: Int?
    public var coverArt: String?
    public var owner:String?
    public var entry: [Song]?
    public init(id: String, name: String, songCount: Int? = nil, duration: Int? = nil, coverArt: String? = nil, entry: [Song]? = nil) { self.id=id; self.name=name; self.songCount=songCount; self.duration=duration; self.coverArt=coverArt; self.entry=entry }
}
public struct Artist: Codable, Identifiable, Hashable, Sendable { public var id: String; public var name: String; public var albumCount: Int?; public var album:[Album]?; public init(id:String,name:String,albumCount:Int?=nil,album:[Album]?=nil){self.id=id;self.name=name;self.albumCount=albumCount;self.album=album} }
public struct SearchResults: Codable, Sendable { public var artist: [Artist]?; public var album: [Album]?; public var song: [Song]?; public init(artist:[Artist]?=nil,album:[Album]?=nil,song:[Song]?=nil){self.artist=artist;self.album=album;self.song=song} }

public struct SubsonicEnvelope: Decodable {
    public let response: SubsonicResponse
    enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}
public struct SubsonicResponse: Decodable {
    public struct APIError: Decodable { public var code: Int; public var message: String }
    public struct AlbumList: Decodable { public var album: [Album]? }
    public struct Playlists: Decodable { public var playlist: [Playlist]? }
    public struct Starred: Decodable { public var song: [Song]?; public var album: [Album]? }
    public struct SongList:Decodable {public var song:[Song]?}
    public struct UserPermissions:Decodable {public var playlistRole:Bool?}
    public var randomSongs:SongList?
    public var similarSongs2:SongList?
    public var user:UserPermissions?
    public var status: String
    public var version: String?
    public var error: APIError?
    public var albumList2: AlbumList?
    public var artist:Artist?
    public var album: Album?
    public var playlists: Playlists?
    public var playlist: Playlist?
    public var searchResult3: SearchResults?
    public var starred2: Starred?
    public func checked() throws -> Self {
        guard status == "ok" else { throw CadenceError.message(error?.message ?? "The server could not complete this request.") }
        return self
    }
}

public struct RunMix: Codable, Equatable, Sendable {
    public static let protocolVersion = 1
    public var version: Int = protocolVersion
    public var id: String
    public var accountKey: String
    public var name: String
    public var songs: [Song]
    public var createdAt: Date
    public var keepOtherMixes:Bool?
    public init(id: String = UUID().uuidString, accountKey: String, name: String, songs: [Song], createdAt: Date = Date()) throws {
        self.id=id; self.accountKey=accountKey; self.name=name; self.songs=songs; self.createdAt=createdAt
        try validate()
    }
    public func validate() throws {
        guard version == Self.protocolVersion, !id.isEmpty, (accountKey == "cadence-demo" || (accountKey.count == 64 && accountKey.allSatisfy { $0.isHexDigit })), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !songs.isEmpty, songs.count <= 100, Set(songs.map(\.id)).count == songs.count else { throw CadenceError.message("Choose between 1 and 100 unique tracks for your Watch mix.") }
    }
    public var durationMinutes: Int { max(1, songs.reduce(0) { $0 + ($1.duration ?? 0) } / 60) }
}
public struct TrackTransfer: Codable, Sendable {
    public var version: Int = RunMix.protocolVersion
    public var mix: RunMix
    public var songID: String
    public var bytes: Int64
    public var sha256: String
    public var artwork: Data?
    public init(mix: RunMix, songID: String, bytes: Int64, sha256: String) { self.mix=mix; self.songID=songID; self.bytes=bytes; self.sha256=sha256 }
    public func validate() throws {
        try mix.validate()
        guard version == RunMix.protocolVersion, mix.songs.contains(where: { $0.id == songID }), bytes > 0, bytes <= 300_000_000, sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else { throw CadenceError.message("The music transfer was incomplete. Send the mix again.") }
    }
}
public struct WatchReceipt: Codable, Sendable {
    public var mixID: String
    public var accountKey: String
    public var readyIDs: [String]
    public var message: String?
    public init(mixID: String, accountKey: String, readyIDs: [String], message: String? = nil) { self.mixID=mixID; self.accountKey=accountKey; self.readyIDs=readyIDs; self.message=message }
}
public enum FileIntegrity {
    public static func sha256(_ url: URL,shouldContinue:()->Bool={true}) throws -> String {
        guard shouldContinue() else{throw CancellationError()}
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty {guard shouldContinue() else{throw CancellationError()};hash.update(data:data)}
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ url: URL, transfer: TrackTransfer,shouldContinue:()->Bool={true}) throws {
        try transfer.validate()
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) == transfer.bytes, try sha256(url,shouldContinue:shouldContinue) == transfer.sha256 else { throw CadenceError.message("A transferred track failed its integrity check. Please resend it.") }
    }
}

public struct PhonePlayback:Codable,Sendable {
    public var song:Song?
    public var isPlaying:Bool
    public var elapsed:Double
    public var duration:Double
    public var shuffled:Bool
    public var repeats:Bool
    public var volume:Double
    public var artwork:Data?
    public var updatedAt:Date
    public init(song:Song?,isPlaying:Bool,elapsed:Double,duration:Double,shuffled:Bool,repeats:Bool,volume:Double,artwork:Data?=nil,updatedAt:Date=Date()){
        self.song=song;self.isPlaying=isPlaying;self.elapsed=elapsed;self.duration=duration;self.shuffled=shuffled;self.repeats=repeats;self.volume=volume;self.artwork=artwork;self.updatedAt=updatedAt
    }
}
public struct PhoneCommand:Codable,Sendable {
    public enum Action:String,Codable,Sendable {case play,pause,next,previous,seek,shuffle,repeatMode,volume}
    public var id=UUID().uuidString
    public var action:Action
    public var value:Double?
    public init(_ action:Action,value:Double?=nil){self.action=action;self.value=value}
    public func validate()throws {
        guard UUID(uuidString:id) != nil else{throw CadenceError.message("Invalid playback command ID.")}
        if [.seek,.volume,.shuffle,.repeatMode].contains(action){guard let value,value.isFinite,value>=0,action == .seek || value<=1 else{throw CadenceError.message("Invalid playback command.")}}
    }
}
public enum CompanionContext {
    public static func update(_ current:[String:Any],fields:[String:Any])->[String:Any]{
        var result=current
        if fields["clearAt"] != nil{result.removeValue(forKey:"mix")}
        if fields["mix"] != nil{result.removeValue(forKey:"clearAt")}
        fields.forEach{result[$0.key]=$0.value};return result
    }
}
