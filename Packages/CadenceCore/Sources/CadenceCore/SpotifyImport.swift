import Foundation

/// Only canonical Spotify playlist links and URIs are accepted. Short links are not followed.
public enum SpotifyPlaylistLink {
    public static func id(_ input:String)->String? {
        let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        let candidate:String
        if text.hasPrefix("spotify:playlist:") { candidate=String(text.dropFirst("spotify:playlist:".count)) }
        else {
            guard let url=URLComponents(string:text),url.scheme=="https",url.host=="open.spotify.com",url.user==nil,url.password==nil,url.port==nil else{return nil}
            var path=url.path.split(separator:"/").map(String.init)
            if path.first?.hasPrefix("intl-")==true {path.removeFirst()}
            guard path.count==2,path[0]=="playlist" else{return nil};candidate=path[1]
        }
        guard candidate.count==22,candidate.utf8.allSatisfy({(48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)}) else{return nil}
        return candidate
    }
}
public struct SpotifyConnection:Decodable,Sendable {public var connected:Bool;public var reconnectRequired:Bool?}
public struct SpotifyImportPreview:Decodable,Sendable {
    public struct Track:Decodable,Sendable {public var artistName:String;public var trackName:String}
    public var trackCount:Int;public var skipped:Int;public var previewTracks:[Track]
}
public struct SpotifyImportReceipt:Decodable,Sendable {public var success:Bool;public var tracksQueued:Int;public var queued:Bool}
public struct ImportedPlaylist:Decodable,Identifiable,Sendable {
    public struct Source:Decodable,Sendable {public var provider:String;public var syncEnabled:Bool}
    public var id:String;public var name:String;public var trackCount:Int;public var importSource:Source?
    public var subsonicID:String {"shared:"+id.addingPercentEncoding(withAllowedCharacters:.alphanumerics.union(CharacterSet(charactersIn:"-_:")))!}
}
public struct PlaylistImportStats:Decodable,Sendable {
    public var total:Int;public var pending:Int;public var downloading:Int;public var blocked:Int;public var done:Int;public var failed:Int
}
public struct PlaylistImportStatus:Decodable,Sendable {
    public var sharedPlaylists:[ImportedPlaylist];public var sharedPlaylistStats:[String:PlaylistImportStats]
    public var spotifyPlaylists:[ImportedPlaylist]{sharedPlaylists.filter{$0.importSource?.provider=="spotify-playlist"}}
    private enum CodingKeys:String,CodingKey{case sharedPlaylists,sharedPlaylistStats,staticPlaylists,staticPlaylistStats}
    public init(from decoder:Decoder)throws{
        let c=try decoder.container(keyedBy:CodingKeys.self)
        // The JSON API renamed these fields in v2; Subsonic still uses shared: IDs.
        sharedPlaylists=try c.decode([ImportedPlaylist].self,forKey:c.contains(.staticPlaylists) ? .staticPlaylists : .sharedPlaylists)
        sharedPlaylistStats=try c.decode([String:PlaylistImportStats].self,forKey:c.contains(.staticPlaylistStats) ? .staticPlaylistStats : .sharedPlaylistStats)
    }
}
public enum SpotifyImportError:Error,LocalizedError {
    case invalidLink,connect,permission,playlistAccess,session,conflict,unavailable,uncertain
    public var errorDescription:String? {switch self {
    case .invalidLink:return "Paste a Spotify playlist link (open.spotify.com/playlist/…). Album and song links aren't playlists."
    case .connect:return "Connect Spotify in Aurral, then return here and check the connection."
    case .permission:return "This Aurral account needs playlist/Flows permission. Ask the server owner to enable it."
    case .playlistAccess:return "Spotify won't allow this connection to read that playlist. Try a playlist you own or collaborate on."
    case .session:return "Your Aurral session expired. Check the connection again, then retry."
    case .conflict:return "A playlist with this name already exists. Choose another name."
    case .unavailable:return "Aurral couldn't read this playlist. Check its Spotify connection, playlist permissions and server access, then try again."
    case .uncertain:return "The import response was interrupted. Check imported playlists or open Aurral before submitting again; the server may have accepted it."
    }}
}
