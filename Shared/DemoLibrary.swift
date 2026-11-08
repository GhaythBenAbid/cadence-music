import Foundation
import CadenceCore

enum DemoLibrary {
    static let songs: [Song] = [
        Song(id:"demo-warmup",title:"First Light",artist:"Cadence Sessions",album:"Easy Miles",albumId:"demo-album",duration:20,contentType:"audio/wav"),
        Song(id:"demo-easy",title:"Find Your Rhythm",artist:"Cadence Sessions",album:"Easy Miles",albumId:"demo-album",duration:20,contentType:"audio/wav"),
        Song(id:"demo-homeward",title:"Homeward",artist:"Cadence Sessions",album:"Easy Miles",albumId:"demo-album",duration:20,contentType:"audio/wav")
    ]
    static let albums=[Album(id:"demo-album",name:"Easy Miles",artist:"Cadence Sessions",songCount:3,year:2026,song:songs)]
    static let playlists=[Playlist(id:"demo-mix",name:"Your next easy run",songCount:3,duration:60,entry:songs)]
    static func url(_ song: Song) -> URL? { Bundle.main.url(forResource:song.id,withExtension:"wav",subdirectory:"Demo") ?? Bundle.main.url(forResource:song.id,withExtension:"wav") }
}
