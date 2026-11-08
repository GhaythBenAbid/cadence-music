#if os(iOS) || os(macOS)
import Foundation
import Network
import CryptoKit
import Combine
import Darwin

/// One bounded encrypted request per connection works when WatchConnectivity wakes iOS.
@MainActor public final class PrivateMacClient:ObservableObject {
    @Published public private(set) var status=MacRemoteStatus()
    @Published public private(set) var endpoint:MacEndpoint?
    private var credentials:ServerCredentials?
    private var generation=UUID()
    private let preferences:UserDefaults
    public init(preferences:UserDefaults = .standard){self.preferences=preferences}
    public func configure(_ value:ServerCredentials?){
        generation=UUID();credentials=value;endpoint=nil;status=MacRemoteStatus();lastResponse=nil
        if let value,let data=preferences.data(forKey:"macEndpoint."+value.accountKey),let saved=try? JSONDecoder().decode(MacEndpoint.self,from:data),MacEndpoint.isTailnetAddress(saved.host){endpoint=saved;status.deviceName=saved.name}
    }
    public func select(_ value:MacEndpoint)throws {
        guard let credentials else{throw CadenceError.message("Sign in to Aurral first.")};try value.validate()
        if endpoint != value{generation=UUID()};endpoint=value;preferences.set(try JSONEncoder().encode(value),forKey:"macEndpoint."+credentials.accountKey)
        status=MacRemoteStatus(deviceName:value.name)
    }
    public func forget(){generation=UUID();if let credentials{preferences.removeObject(forKey:"macEndpoint."+credentials.accountKey)};endpoint=nil;status=MacRemoteStatus()}
    @Published public private(set) var lastResponse:MacRemoteResponse?
    private var phoneID:String{let key="cadence.phoneDeviceID";if let id=preferences.string(forKey:key){return id};let id=UUID().uuidString;preferences.set(id,forKey:key);return id}
    public func transfer(_ transfer:PlaybackTransfer,id:String=UUID().uuidString)async throws->TransferredPlayback {
        try transfer.validate()
        // Old servers must never interpret an unsupported transfer as a harmless status poll.
        let identity=credentials,selected=endpoint,stamp=generation
        _=try await fetch()
        guard identity==credentials,selected==endpoint,stamp==generation else{throw CancellationError()}
        guard lastResponse?.capabilities?.contains("handoff-v1")==true else{throw CadenceError.message("Update Cadence on your Mac to use playback handoff.")}
        var request=MacRemoteRequest(id:id);request.transfer=transfer
        let reply=try await exchange(request)
        guard let result=reply.transfer else{throw CadenceError.message("The Mac didn't confirm the transfer. Keep the source paused and check its status before retrying.")};return result
    }
    public func poll(phonePlayback:PhonePlayback,acknowledged:String?=nil)async throws->MacRemoteResponse{
        let identity=credentials,selected=endpoint,stamp=generation
        if lastResponse?.capabilities?.contains("handoff-v1") != true{
            _=try await fetch()
            guard identity==credentials,selected==endpoint,stamp==generation,let response=lastResponse else{throw CancellationError()}
            // Older Macs accept only small control requests. Keep their existing controls usable.
            if response.capabilities?.contains("handoff-v1") != true{return response}
        }
        var request=MacRemoteRequest();request.acceptsHandoff=true;request.phonePlayback=phonePlayback;request.acknowledgedInstruction=acknowledged
        return try await exchange(request)
    }
    public func fetch(_ command:PhoneCommand?=nil) async throws->PhonePlayback {
        let response=try await exchange(MacRemoteRequest(command:command))
        guard let playback=response.playback else{throw CadenceError.message("The Mac didn't return playback state.")};return playback
    }
    private func exchange(_ value:MacRemoteRequest)async throws->MacRemoteResponse{
        guard let credentials,let endpoint else{throw CadenceError.message("Connect your Mac in Cadence on iPhone first.")}
        let checkedAt=Date(),stamp=generation,key=MacRemoteCrypto.key(credentials)
        var request=value;request.clientID=phoneID
        do{
            let packet=try MacRemoteCrypto.seal(request,key:key,maximum:2_000_000)
            let data=try await MacWire.exchange(host:endpoint.host,port:endpoint.port,packet:packet)
            let response=try MacRemoteCrypto.open(MacRemoteResponse.self,data:data,key:key,maximum:2_000_100);try response.validate(requestID:request.id)
            guard self.credentials==credentials,self.endpoint==endpoint,self.generation==stamp else{throw CancellationError()}
            if let error=response.error{throw CadenceError.message(error)}
            guard let playback=response.playback else{throw CadenceError.message("The Mac didn't return playback state.")}
            if checkedAt>=status.checkedAt{lastResponse=response;status=MacRemoteStatus(playback:playback,deviceName:endpoint.name,connected:true,checkedAt:checkedAt)};return response
        }catch{
            if self.credentials==credentials,self.endpoint==endpoint,self.generation==stamp,checkedAt>=status.checkedAt{lastResponse=nil;status=MacRemoteStatus(playback:status.playback,deviceName:endpoint.name,message:"Mac unavailable. Keep Tailscale and Cadence open on both devices; leave the source paused if a transfer wasn't confirmed.",checkedAt:checkedAt)}
            throw error
        }
    }
}

@MainActor enum MacWire {
    static func frame(_ data:Data)->Data {var length=UInt32(data.count).bigEndian;var result=withUnsafeBytes(of:&length){Data($0)};result.append(data);return result}
    static func receive(_ connection:NWConnection,maximum:Int=2_000_100,completion:@escaping(Result<Data,Error>)->Void){
        read(connection,count:4){header in
            switch header{
            case .failure(let error):completion(.failure(error))
            case .success(let bytes):
                let count=bytes.reduce(0){($0<<8)|Int($1)}
                guard count>0,count<=maximum else{completion(.failure(CadenceError.message("Invalid remote frame.")));return}
                read(connection,count:count,completion:completion)
            }
        }
    }
    private static func read(_ connection:NWConnection,count:Int,completion:@escaping(Result<Data,Error>)->Void){
        connection.receive(minimumIncompleteLength:count,maximumLength:count){data,_,_,error in
            Task{@MainActor in
                if let error{completion(.failure(error))}
                else if let data,data.count==count{completion(.success(data))}
                else{completion(.failure(CadenceError.message("The Mac connection closed before replying.")))}
            }
        }
    }
    static func exchange(host:String,port:UInt16,packet:Data)async throws->Data{
        guard MacEndpoint.isTailnetAddress(host),let port=NWEndpoint.Port(rawValue:port) else{throw CadenceError.message("Only private Tailscale addresses can be used for Mac control.")}
        return try await withCheckedThrowingContinuation{continuation in
            let request=MacWireRequest(connection:NWConnection(host:NWEndpoint.Host(host),port:port,using:.tcp),packet:packet,continuation:continuation)
            request.start()
        }
    }
}
@MainActor private final class MacWireRequest {
    let connection:NWConnection
    let packet:Data
    var continuation:CheckedContinuation<Data,Error>?
    var timeout:Task<Void,Never>?
    init(connection:NWConnection,packet:Data,continuation:CheckedContinuation<Data,Error>){self.connection=connection;self.packet=packet;self.continuation=continuation}
    func start(){
        // The connection's handlers retain this operation until finish clears them.
        connection.stateUpdateHandler={state in Task{@MainActor in
            switch state{
            case .ready:self.connection.send(content:MacWire.frame(self.packet),completion:.contentProcessed{error in Task{@MainActor in
                if let error{self.finish(.failure(error))}else{MacWire.receive(self.connection){self.finish($0)}}
            }})
            case .failed(let error):self.finish(.failure(error))
            default:break
            }
        }}
        timeout=Task{try? await Task.sleep(for:.seconds(4));if !Task.isCancelled{finish(.failure(CadenceError.message("The Mac isn't reachable through Tailscale.")))}}
        connection.start(queue:.global(qos:.userInitiated))
    }
    func finish(_ result:Result<Data,Error>){guard let continuation else{return};self.continuation=nil;timeout?.cancel();connection.stateUpdateHandler=nil;connection.cancel();continuation.resume(with:result)}
}

#if os(macOS)
@MainActor public final class PrivateMacServer:ObservableObject {
    @Published public private(set) var endpoint:MacEndpoint?
    @Published public private(set) var message="Sign in to enable Watch control."
    public var playback:(()->PhonePlayback)?
    public var transfer:((PlaybackTransfer)throws->TransferredPlayback)?
    @Published public private(set) var phoneAvailable=false
    @Published public private(set) var phonePlayback:PhonePlayback?
    @Published public var playingOnPhone=false
    @Published public private(set) var pendingInstruction:PhoneInstruction?
    private var phoneID:String?
    private var phoneExpiry:Task<Void,Never>?
    private var instructionExpiry:Task<Void,Never>?
    @Published public private(set) var lastAcknowledgedInstructionID:String?
    private var awaitingInstructionID:String?
    private var lastTransferID:String?
    public func useLocalPlayback(){instructionExpiry?.cancel();pendingInstruction=nil;awaitingInstructionID=nil;playingOnPhone=false}
    public func instructPhone(_ instruction:PhoneInstruction)throws {
        guard phoneAvailable else{throw CadenceError.message("Open Cadence on your paired iPhone and keep it in the foreground to transfer or control playback.")}
        try instruction.validate();pendingInstruction=instruction
        instructionExpiry?.cancel();instructionExpiry=Task{[weak self] in try? await Task.sleep(for:.seconds(25));guard !Task.isCancelled,let self,self.pendingInstruction?.id==instruction.id else{return};self.pendingInstruction=nil;self.message="The iPhone didn't confirm the request. Open Cadence on it and try again."}
    }
    public var command:((PhoneCommand)throws->PhonePlayback)?
    private var listener:NWListener?
    private var boundHost:String?
    private let advertise:Bool
    private var advertiser:NetService?
    private var monitor:NWPathMonitor?
    private var credentials:ServerCredentials?
    private var replay=MacRemoteReplayGuard()
    private var connections:[UUID:NWConnection]=[:]
    private var generation=UUID()
    private let deviceID:String
    private let port:UInt16
    public init(port:UInt16=MacEndpoint.defaultPort,preferences:UserDefaults = .standard,advertise:Bool=true){
        self.port=port;self.advertise=advertise
        let key="cadence.macDeviceID";deviceID=preferences.string(forKey:key) ?? UUID().uuidString;preferences.set(deviceID,forKey:key)
    }
    public func configure(_ credentials:ServerCredentials?){
        stop();self.credentials=credentials;replay=MacRemoteReplayGuard()
        guard credentials != nil else{message="Sign in with the same Aurral account on Mac and iPhone.";return}
        let monitor=NWPathMonitor();self.monitor=monitor;monitor.pathUpdateHandler={ [weak self] _ in Task{@MainActor in self?.refreshNetwork()}};monitor.start(queue:.global(qos:.utility));refreshNetwork()
    }
    public func stop(){
        generation=UUID();phoneExpiry?.cancel();instructionExpiry?.cancel();phoneAvailable=false;phonePlayback=nil;phoneID=nil;pendingInstruction=nil;playingOnPhone=false;lastTransferID=nil;lastAcknowledgedInstructionID=nil;awaitingInstructionID=nil;monitor?.cancel();monitor=nil;listener?.cancel();listener=nil;boundHost=nil;advertiser?.stop();advertiser=nil;connections.values.forEach{$0.cancel()};connections=[:];endpoint=nil;credentials=nil
    }
    public func refreshNetwork(){
        guard let credentials else{return}
        guard let host=TailnetInterface.address() else{listener?.cancel();listener=nil;boundHost=nil;advertiser?.stop();advertiser=nil;endpoint=nil;message="Connect Tailscale on this Mac to enable Watch control.";return}
        if boundHost==host,listener != nil{return}
        listener?.cancel();advertiser?.stop();generation=UUID();let token=generation
        do{
            let name=String((Host.current().localizedName ?? "Mac").prefix(100))
            let endpoint=try MacEndpoint(id:deviceID,name:name,host:host,port:port)
            let parameters=NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host:.ipv4(IPv4Address(host)!),port:NWEndpoint.Port(rawValue:endpoint.port)!)
            let listener=try NWListener(using:parameters)
            self.listener=listener;self.boundHost=host
            listener.stateUpdateHandler={ [weak self] state in Task{@MainActor in
                guard let self,self.generation==token else{return}
                switch state{
                case .ready:
                    self.endpoint=endpoint;self.message="Ready for private Watch control through your iPhone."
                    guard self.advertise else{return}
                    let service=NetService(domain:"local.",type:"_cadence-remote._tcp.",name:"Cadence · "+name,port:Int32(endpoint.port))
                    service.setTXTRecord(NetService.data(fromTXTRecord:["host":Data(host.utf8),"account":Data(credentials.accountKey.utf8),"id":Data(self.deviceID.utf8),"name":Data(name.utf8)]));self.advertiser=service;service.publish()
                case .failed: self.message="Mac control couldn't start. Reconnect Tailscale and try again.";self.endpoint=nil;self.listener=nil;self.boundHost=nil
                default:break
                }
            }}
            listener.newConnectionHandler={ [weak self] connection in Task{@MainActor in self?.accept(connection,generation:token)}}
            listener.start(queue:.global(qos:.userInitiated))
        }catch{message="Mac control couldn't start: "+error.localizedDescription;endpoint=nil}
    }
    private func accept(_ connection:NWConnection,generation token:UUID){
        guard token==generation,connections.count<16,let credentials else{connection.cancel();return}
        let id=UUID(),key=MacRemoteCrypto.key(credentials);connections[id]=connection
        let timeout=Task{try? await Task.sleep(for:.seconds(5));if !Task.isCancelled{connection.cancel();connections.removeValue(forKey:id)}}
        connection.start(queue:.global(qos:.userInitiated))
        MacWire.receive(connection,maximum:2_000_100){ [weak self] result in
            guard let self,self.generation==token else{timeout.cancel();connection.cancel();return}
            do{
                let data=try result.get(),request=try MacRemoteCrypto.open(MacRemoteRequest.self,data:data,key:key,maximum:2_000_100)
                try request.validate()
                if request.acceptsHandoff==true,let id=request.clientID,UUID(uuidString:id) != nil{
                    // Never advertise a suspended phone as a destination merely because Watch polling woke it.
                    if self.phoneID != id{self.pendingInstruction=nil};self.phoneID=id;self.phoneAvailable=true;self.phonePlayback=request.phonePlayback
                    if let ack=request.acknowledgedInstruction,ack==self.pendingInstruction?.id || ack==self.awaitingInstructionID{self.lastAcknowledgedInstructionID=ack;if self.pendingInstruction?.id==ack{self.pendingInstruction=nil};if self.awaitingInstructionID==ack{self.awaitingInstructionID=nil}}
                    self.phoneExpiry?.cancel();self.phoneExpiry=Task{[weak self] in try? await Task.sleep(for:.seconds(8));guard !Task.isCancelled else{return};self?.phoneAvailable=false}
                }
                var response:MacRemoteResponse
                if let operation=request.transfer{
                    response=try self.replay.executeTransfer(request){
                        guard let handler=self.transfer else{throw CadenceError.message("Update Cadence on this Mac to enable handoff.")}
                        let transferred=try handler(operation)
                        if operation.direction == .toMac || operation.direction == .toPhone{self.playingOnPhone=operation.direction == .toPhone;if self.pendingInstruction?.id==request.id{self.awaitingInstructionID=request.id};self.pendingInstruction=nil;self.lastTransferID=request.id}
                        var result=MacRemoteResponse(id:request.id,playback:self.playback?());result.transfer=transferred;return result
                    }
                }else{
                    response=try self.replay.execute(request){
                        if let command=request.command,let handler=self.command{return try handler(command)}
                        guard request.command==nil,let state=self.playback?() else{throw CadenceError.message("Open Cadence on your Mac first.")};return state
                    }
                }
                response.capabilities=self.transfer == nil ? [] : ["handoff-v1"];response.lastTransferID=self.lastTransferID
                if request.acceptsHandoff==true,request.clientID==self.phoneID{response.instruction=self.pendingInstruction}
                let packet=try MacRemoteCrypto.seal(response,key:key,maximum:2_000_000)
                connection.send(content:MacWire.frame(packet),completion:.contentProcessed{_ in Task{@MainActor in timeout.cancel();connection.cancel();self.connections.removeValue(forKey:id)}})
            }catch{timeout.cancel();connection.cancel();self.connections.removeValue(forKey:id)}
        }
    }
}
/// Match Tailscale's ULA as well as CGNAT IPv4; other VPNs can also use 100.x addresses.
enum TailnetInterface {
    static func address()->String?{
        var first:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first)==0,let first else{return nil};defer{freeifaddrs(first)}
        var names=Set<String>(),addresses:[String:String]=[:],current:UnsafeMutablePointer<ifaddrs>?=first
        while let item=current{
            defer{current=item.pointee.ifa_next}
            guard let addr=item.pointee.ifa_addr else{continue};let name=String(cString:item.pointee.ifa_name)
            guard name.hasPrefix("utun") else{continue}
            var host=[CChar](repeating:0,count:Int(NI_MAXHOST))
            guard getnameinfo(addr,socklen_t(addr.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0 else{continue}
            let value=String(cString:host).lowercased()
            if addr.pointee.sa_family==UInt8(AF_INET6),value.hasPrefix("fd7a:115c:a1e0:"){names.insert(name)}
            if addr.pointee.sa_family==UInt8(AF_INET),MacEndpoint.isTailnetAddress(value){addresses[name]=value}
        }
        return names.sorted().compactMap{addresses[$0]}.first
    }
}
#endif
#endif
