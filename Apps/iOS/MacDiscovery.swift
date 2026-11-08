import Foundation
import Combine
import CadenceCore

@MainActor final class MacDiscovery:NSObject,ObservableObject,NetServiceBrowserDelegate,NetServiceDelegate {
    @Published private(set) var devices:[MacEndpoint]=[]
    @Published private(set) var message:String?
    var onFound:((MacEndpoint)->Void)?
    private var browser:NetServiceBrowser?
    private var services:[ObjectIdentifier:NetService]=[:]
    private var account:String?
    func configure(_ credentials:ServerCredentials?){
        browser?.stop();services.values.forEach{$0.stop()};services=[:];devices=[];account=credentials?.accountKey;message=nil
        guard credentials != nil else{browser=nil;return}
        let browser=NetServiceBrowser();self.browser=browser;browser.delegate=self;browser.searchForServices(ofType:"_cadence-remote._tcp.",inDomain:"local.")
    }
    nonisolated func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool){
        Task{@MainActor in guard browser===self.browser else{return};self.services[ObjectIdentifier(service)]=service;service.delegate=self;service.resolve(withTimeout:5)}
    }
    nonisolated func netServiceDidResolveAddress(_ sender:NetService){
        Task{@MainActor in
            guard self.services[ObjectIdentifier(sender)] != nil,let data=sender.txtRecordData() else{return}
            let values=NetService.dictionary(fromTXTRecord:data)
            func value(_ key:String)->String{values[key].flatMap{String(data:$0,encoding:.utf8)} ?? ""}
            guard value("account")==self.account,let port=UInt16(exactly:sender.port),let device=try? MacEndpoint(id:value("id"),name:value("name"),host:value("host"),port:port) else{return}
            self.devices.removeAll{$0.id==device.id};self.devices.append(device);self.devices.sort{$0.name<$1.name};self.onFound?(device)
        }
    }
    nonisolated func netServiceBrowser(_ browser:NetServiceBrowser,didNotSearch errorDict:[String:NSNumber]){
        Task{@MainActor in guard browser===self.browser else{return};self.message="Allow Local Network access to find nearby Macs, or paste the Mac connection link."}
    }
}
