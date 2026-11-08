import Foundation
import SwiftUI
import CadenceCore

/// Independent from the replaceable Watch mix and its erase requests.
@MainActor final class DeviceDownloads:ObservableObject {
    @Published private(set) var songs:[Song]=[]
    private(set) var account:String?
    let root:URL
    init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadencePhoneDownloads",isDirectory:true)}
    func configure(account:String?){
        self.account=account.flatMap{($0=="cadence-demo" || ($0.count==64 && $0.allSatisfy(\.isHexDigit))) ? $0 : nil};songs=[]
        guard let folder=folder,let data=try? Data(contentsOf:folder.appendingPathComponent("downloads.json")),let saved=try? JSONDecoder().decode([Song].self,from:data) else{return}
        songs=saved.filter{url($0) != nil}
    }
    private var folder:URL?{account.map{root.appendingPathComponent($0,isDirectory:true)}}
    func url(_ song:Song)->URL?{
        guard let target=folder?.appendingPathComponent(song.filename),let size=try? target.resourceValues(forKeys:[.fileSizeKey]).fileSize,size>0 else{return nil};return target
    }
    func contains(_ song:Song)->Bool{url(song) != nil}
    func save(_ source:URL,song:Song,account:String)throws {
        guard self.account==account,let folder,(account=="cadence-demo" || (account.count==64 && account.allSatisfy(\.isHexDigit))) else{throw CancellationError()}
        let size=try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size>0,size<=300_000_000 else{throw CadenceError.message("The download is empty or too large.")}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let target=folder.appendingPathComponent(song.filename)
        if FileManager.default.fileExists(atPath:target.path){try FileManager.default.removeItem(at:target)}
        try FileManager.default.moveItem(at:source,to:target)
        let next=songs.filter{$0.id != song.id}+[song]
        do{try JSONEncoder().encode(next).write(to:folder.appendingPathComponent("downloads.json"),options:.atomic)}catch{try? FileManager.default.removeItem(at:target);throw error}
        var values=URLResourceValues();values.isExcludedFromBackup=true;var location=folder;try? location.setResourceValues(values)
        songs=next
    }
    func remove(_ song:Song)throws{
        guard let folder else{return}
        let next=songs.filter{$0.id != song.id}
        try JSONEncoder().encode(next).write(to:folder.appendingPathComponent("downloads.json"),options:.atomic)
        try? FileManager.default.removeItem(at:folder.appendingPathComponent(song.filename));songs=next
    }
    func eraseAll(){try? FileManager.default.removeItem(at:root);account=nil;songs=[]}
}
