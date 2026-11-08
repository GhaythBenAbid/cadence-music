import Foundation
import AVFoundation
import CadenceCore
@main struct Probe {
    static func main() async {
        do {
            if ProcessInfo.processInfo.arguments.contains("--native-contract-check"){try await NativeContractProbe.run();return}
            #if os(macOS)
            if ProcessInfo.processInfo.arguments.contains("--mac-remote-self-test"){try await MacRemoteProbe.run();return}
            #endif
            let env=ProcessInfo.processInfo.environment
            guard let server=env["CADENCE_SERVER"], let username=env["CADENCE_USERNAME"], let password=env["CADENCE_PASSWORD"] else { throw CadenceError.message("Set CADENCE_SERVER, CADENCE_USERNAME and CADENCE_PASSWORD privately in the environment.") }
            let api=SubsonicAPI(credentials:.init(server:try ServerCredentials.normalizedServer(server),username:username,password:password))
            try await api.ping(); print("PASS: authenticated Subsonic ping")
            let albums=try await api.albums();print("PASS: album decoding (\(albums.count) albums)")
            let playlists=try await api.playlists();print("PASS: playlist decoding (\(playlists.count) playlists)")
            let search=try await api.search("Carefree");guard let song=search.song?.first else { throw CadenceError.message("No test song available") }
            let stream=api.authenticatedURL("stream",parameters:[.init(name:"id",value:song.id)])
            guard try await AVURLAsset(url:stream).load(.isPlayable) else { throw CadenceError.message("The authenticated stream is not playable") };print("PASS: authenticated stream playable by AVFoundation")
            let url=try await api.download(song);defer {try? FileManager.default.removeItem(at:url)}
            let bytes=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            print("PASS: authenticated audio download (\(bytes) bytes)")
            let audio=url.appendingPathExtension(song.audioExtension);try FileManager.default.copyItem(at:url,to:audio);defer{try? FileManager.default.removeItem(at:audio)}
            print("INFO: content type \(song.contentType ?? "unknown")"); let playable=try await AVURLAsset(url:audio).load(.isPlayable)
            guard playable else{throw CadenceError.message("Downloaded audio is not playable by AVFoundation")};print("PASS: cached audio playable by AVFoundation")
            let duration=try await AVURLAsset(url:audio).load(.duration).seconds
            guard duration>180 else {throw CadenceError.message("Expected a complete test track, not a preview")};print("PASS: full cached track duration \(Int(duration)) seconds")
            if let id=song.albumId { _ = try await api.album(id); print("PASS: album detail decoding") }
            if let playlist=playlists.first { _ = try await api.playlist(playlist.id);print("PASS: playlist detail decoding") }
        } catch { fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1) }
    }
}
