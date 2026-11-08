import Foundation
import UIKit
import CadenceCore

struct PhoneDownloadJob:Codable,Identifiable,Equatable {
    enum State:String,Codable {case queued,running,paused,failed}
    var id=UUID().uuidString
    var account:String
    var song:Song
    var state:State = .queued
    var progress:Double=0
    var message:String?
}

/// The system owns network transfers; the app owns account checks and atomic catalog imports.
@MainActor final class PhoneDownloadManager:NSObject,ObservableObject {
    static let shared=PhoneDownloadManager()
    static let identifier="com.bahachammakhi.cadencemusic.phone-downloads"
    let downloads:DeviceDownloads
    private let suppliedConfiguration:URLSessionConfiguration?
    @Published private(set) var jobs:[PhoneDownloadJob]=[]
    @Published var cellular=UserDefaults.standard.bool(forKey:"downloads.cellular") {didSet{UserDefaults.standard.set(cellular,forKey:"downloads.cellular")}}
    var backgroundCompletion:(()->Void)?
    var onFilesReady:(()async->Void)?
    private var credentials:ServerCredentials?
    private var account:String?
    private(set) var restored=false
    private var tasks:[String:URLSessionDownloadTask]=[:]
    private let root:URL
    nonisolated private let inbox:URL
    private lazy var session:URLSession={
        let configuration=suppliedConfiguration ?? URLSessionConfiguration.background(withIdentifier:Self.identifier)
        configuration.isDiscretionary=false;configuration.sessionSendsLaunchEvents=true;configuration.waitsForConnectivity=true
        configuration.timeoutIntervalForResource=7*24*60*60
        return URLSession(configuration:configuration,delegate:self,delegateQueue:nil)
    }()
    init(configuration:URLSessionConfiguration?=nil,root:URL?=nil,downloads:DeviceDownloads?=nil,credentials:ServerCredentials?=KeychainStore.load()){
        self.inbox=root?.appendingPathComponent("inbox",isDirectory:true) ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceDownloadInbox",isDirectory:true)
        self.suppliedConfiguration=configuration;self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceDownloadJobs",isDirectory:true);self.downloads=downloads ?? DeviceDownloads()
        super.init()
        self.credentials=credentials;account=credentials?.accountKey;self.downloads.configure(account:account)
        if let data=try? Data(contentsOf:self.root.appendingPathComponent("jobs.json")),let saved=try? JSONDecoder().decode([PhoneDownloadJob].self,from:data){jobs=saved.filter{$0.account==account}}
        let _=session
        session.getAllTasks{[weak self] found in Task{@MainActor in
            guard let self else{return}
            for task in found{guard let task=task as? URLSessionDownloadTask,let id=task.taskDescription,self.jobs.contains(where:{$0.id==id && $0.account==self.account && $0.state == .running}) else{task.cancel();continue};self.tasks[id]=task}
            self.importInbox()
            for i in self.jobs.indices where self.jobs[i].state == .running && self.tasks[self.jobs[i].id]==nil{self.jobs[i].state = .queued}
            self.restored=true;self.persist();self.schedule();await self.onFilesReady?()
        }}
    }
    func configure(_ credentials:ServerCredentials?,demo:Bool=false){
        let next=credentials?.accountKey ?? (demo ? "cadence-demo" : nil)
        self.credentials=credentials
        guard next != account else{return}
        cancelAll();account=next;downloads.configure(account:next);persist()
    }
    func enqueue(_ songs:[Song]){
        guard let account else{return}
        for song in songs where !downloads.contains(song) && !jobs.contains(where:{$0.song.id==song.id && $0.account==account}){jobs.append(PhoneDownloadJob(account:account,song:song))}
        persist();schedule()
    }
    func pause(_ id:String){
        guard let i=jobs.firstIndex(where:{$0.id==id}) else{return};jobs[i].state = .paused;persist()
        if let task=tasks.removeValue(forKey:id){task.cancel(byProducingResumeData:{[weak self] data in Task{@MainActor in
            guard let self,self.jobs.contains(where:{$0.id==id && $0.state == .paused}),let data else{return};try? data.write(to:self.resumeURL(id),options:.atomic)
        }})};schedule()
    }
    func retry(_ id:String){guard let i=jobs.firstIndex(where:{$0.id==id}),jobs[i].state != .running else{return};jobs[i].state = .queued;jobs[i].message=nil;persist();schedule()}
    func cancel(_ id:String){tasks.removeValue(forKey:id)?.cancel();jobs.removeAll{$0.id==id};try? FileManager.default.removeItem(at:resumeURL(id));persist();schedule()}
    func close(){cancelAll();session.invalidateAndCancel()}
    func cancelAll(){let old=tasks.values;tasks=[:];jobs=[];for task in old{task.cancel()};try? FileManager.default.removeItem(at:root);persist()}
    private func resumeURL(_ id:String)->URL{root.appendingPathComponent(id+".resume")}
    private func persist(){
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try? JSONEncoder().encode(jobs).write(to:root.appendingPathComponent("jobs.json"),options:.atomic)
        var values=URLResourceValues();values.isExcludedFromBackup=true;var directory=root;try? directory.setResourceValues(values)
    }
    private func schedule(){
        guard restored else{return}
        while tasks.count<2,let i=jobs.firstIndex(where:{$0.state == .queued && $0.account==account}){
            let job=jobs[i]
            if account=="cadence-demo"{
                do{guard let source=DemoLibrary.url(job.song) else{throw CadenceError.message("Demo audio is unavailable.")};let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.copyItem(at:source,to:temp);try downloads.save(temp,song:job.song,account:job.account);jobs.remove(at:i)}catch{jobs[i].state = .failed;jobs[i].message="Couldn't save this track. Try again."};persist();continue
            }
            guard let credentials,credentials.accountKey==job.account else{return}
            let task:URLSessionDownloadTask
            if let data=try? Data(contentsOf:resumeURL(job.id)){task=session.downloadTask(withResumeData:data);try? FileManager.default.removeItem(at:resumeURL(job.id))}
            else{var request=URLRequest(url:SubsonicAPI(credentials:credentials).authenticatedURL("download",parameters:[.init(name:"id",value:job.song.id)]));request.allowsCellularAccess=cellular;task=session.downloadTask(with:request)}
            task.taskDescription=job.id;tasks[job.id]=task;jobs[i].state = .running;persist();task.resume()
        }
    }
    private func importInbox(){
        let files=(try? FileManager.default.contentsOfDirectory(at:inbox,includingPropertiesForKeys:nil)) ?? []
        for source in files where UUID(uuidString:source.lastPathComponent) != nil{
            let id=source.lastPathComponent
            defer{try? FileManager.default.removeItem(at:source)}
            guard let job=jobs.first(where:{$0.id==id && $0.account==account}) else{continue}
            do{try downloads.save(source,song:job.song,account:job.account);jobs.removeAll{$0.id==id};tasks.removeValue(forKey:id)?.cancel();try? FileManager.default.removeItem(at:resumeURL(id))}
            catch{if let i=jobs.firstIndex(where:{$0.id==id}){jobs[i].state = .failed;jobs[i].message="Couldn't save this track. Try again."}}
        };persist()
    }
    func finishBackgroundEvents()async{importInbox();schedule();await onFilesReady?();let completion=backgroundCompletion;backgroundCompletion=nil;completion?()}
}

extension PhoneDownloadManager:URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){
        guard let id=downloadTask.taskDescription,UUID(uuidString:id) != nil else{return}
        // A delegate's temporary URL expires when this callback returns.
        do{
            guard let http=downloadTask.response as? HTTPURLResponse,(200..<300).contains(http.statusCode),let mime=http.mimeType,mime.hasPrefix("audio/") || mime=="application/octet-stream" else{throw CadenceError.message("This track couldn't be downloaded.")}
            let bytes=try location.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard bytes>0,bytes<=300_000_000 else{throw CadenceError.message("This track is empty or too large.")}
            try FileManager.default.createDirectory(at:inbox,withIntermediateDirectories:true)
            try FileManager.default.moveItem(at:location,to:inbox.appendingPathComponent(id))
            Task{@MainActor [weak self] in self?.importInbox();self?.schedule();await self?.onFilesReady?()}
        }catch{Task{@MainActor [weak self] in guard let self,self.tasks[id] === downloadTask else{return};self.failed(id,message:"Couldn't download this track. Check your server connection and retry.")}}
    }
    nonisolated func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){
        guard let id=downloadTask.taskDescription,totalBytesExpectedToWrite>0 else{return}
        Task{@MainActor [weak self] in guard let self,let i=self.jobs.firstIndex(where:{$0.id==id && $0.state == .running}) else{return};self.jobs[i].progress=max(0,min(1,Double(totalBytesWritten)/Double(totalBytesExpectedToWrite)))}
    }
    nonisolated func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        guard let id=task.taskDescription else{return}
        Task{@MainActor [weak self] in
            guard let self else{return};guard self.tasks[id] === task else{return};self.tasks.removeValue(forKey:id)
            if let error,let i=self.jobs.firstIndex(where:{$0.id==id && $0.state == .running}){
                if let data=(error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data{try? data.write(to:self.resumeURL(id),options:.atomic)}
                self.jobs[i].state = .failed;self.jobs[i].message="Download interrupted. Check your server connection and retry.";self.persist()
            };self.importInbox();self.schedule();await self.onFilesReady?()
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session:URLSession){Task{@MainActor [weak self] in await self?.finishBackgroundEvents()}}
    private func failed(_ id:String,message:String){guard let i=jobs.firstIndex(where:{$0.id==id}) else{return};tasks.removeValue(forKey:id);jobs[i].state = .failed;jobs[i].message=message;persist();schedule()}
}

final class PhoneAppDelegate:NSObject,UIApplicationDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{_ = PhoneStore.shared;return true}
    func application(_ application:UIApplication,handleEventsForBackgroundURLSession identifier:String,completionHandler:@escaping()->Void){
        guard identifier==PhoneDownloadManager.identifier else{completionHandler();return}
        _ = PhoneStore.shared
        PhoneDownloadManager.shared.backgroundCompletion=completionHandler
    }
}
