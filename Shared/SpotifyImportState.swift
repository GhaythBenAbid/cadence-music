#if os(iOS) || os(macOS)
import SwiftUI
import CadenceCore

@MainActor final class SpotifyImportState:ObservableObject {
    @Published var connection:SpotifyConnection?
    @Published var status:PlaylistImportStatus?
    @Published var connectionError:String?
    @Published var statusError:String?
    @Published var checking=false
    @Published var acceptedName:String?
    @Published var acceptedCount=0
    @Published var updatedAt:Date?
    @Published var revision=0
    private var generation=UUID()
    func reset(){generation=UUID();connection=nil;status=nil;connectionError=nil;statusError=nil;checking=false;acceptedName=nil;acceptedCount=0;updatedAt=nil}
    func reload(quiet:Bool=false,connection loadConnection:()async throws->SpotifyConnection,imports loadImports:()async throws->PlaylistImportStatus)async {
        guard !checking else{return}
        let stamp=generation;checking=true
        defer{if stamp==generation{checking=false}}
        // Existing audio does not depend on a healthy Spotify OAuth connection.
        do{
            let fresh=try await loadImports();guard stamp==generation else{return}
            let before=fingerprint(status),after=fingerprint(fresh)
            status=fresh;updatedAt=Date();statusError=nil
            if before != after{revision += 1}
        }catch is CancellationError{return}
        catch{guard stamp==generation else{return};statusError=error.localizedDescription}
        do{let fresh=try await loadConnection();guard stamp==generation else{return};connection=fresh;connectionError=nil}
        catch is CancellationError{return}
        catch{guard stamp==generation else{return};connection=nil;connectionError=error.localizedDescription}
    }
    private func fingerprint(_ value:PlaylistImportStatus?)->String {
        guard let value else{return ""}
        return value.spotifyPlaylists.map{playlist in
            let counts=value.sharedPlaylistStats[playlist.id]
            return "\(playlist.id)|\(playlist.name)|\(playlist.trackCount)|\(counts?.done ?? 0)|\(counts?.pending ?? 0)|\(counts?.downloading ?? 0)|\(counts?.failed ?? 0)|\(counts?.blocked ?? 0)"
        }.sorted().joined(separator:";")
    }
}
#endif
