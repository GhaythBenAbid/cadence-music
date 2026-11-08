import Foundation
import CryptoKit

public struct MacEndpoint:Codable,Equatable,Identifiable,Sendable {
    public static let defaultPort:UInt16=47823
    public var id:String
    public var name:String
    public var host:String
    public var port:UInt16
    public init(id:String,name:String,host:String,port:UInt16=defaultPort)throws{
        guard UUID(uuidString:id) != nil,!name.isEmpty,name.count<=128,Self.isTailnetAddress(host),port>0 else{throw CadenceError.message("Enter this Mac's Tailscale IPv4 address (100.x.x.x).")}
        self.id=id;self.name=name;self.host=host;self.port=port
    }
    public func validate()throws{
        guard UUID(uuidString:id) != nil,!name.isEmpty,name.count<=128,Self.isTailnetAddress(host),port>0 else{throw CadenceError.message("Only a private Tailscale Mac endpoint can be connected.")}
    }
    private enum CodingKeys:String,CodingKey{case id,name,host,port}
    public init(from decoder:Decoder)throws{
        let c=try decoder.container(keyedBy:CodingKeys.self);id=try c.decode(String.self,forKey:.id);name=try c.decode(String.self,forKey:.name);host=try c.decode(String.self,forKey:.host);port=try c.decode(UInt16.self,forKey:.port);try validate()
    }
    public static func isTailnetAddress(_ host:String)->Bool{
        let fields=host.split(separator:".",omittingEmptySubsequences:false)
        guard fields.count==4,fields.allSatisfy({!$0.isEmpty && $0.allSatisfy(\.isNumber) && String(Int($0) ?? -1)==$0}),let a=Int(fields[0]),let b=Int(fields[1]),fields.allSatisfy({(0...255).contains(Int($0) ?? -1)}) else{return false}
        return a==100 && (64...127).contains(b)
    }
    public var connectionURL:URL {
        var url=URLComponents();url.scheme="cadence";url.host="mac";url.queryItems=[.init(name:"id",value:id),.init(name:"name",value:name),.init(name:"host",value:host),.init(name:"port",value:String(port))];return url.url!
    }
    public static func from(_ url:URL)throws->Self{
        guard url.scheme=="cadence",url.host=="mac",let parts=URLComponents(url:url,resolvingAgainstBaseURL:false) else{throw CadenceError.message("This isn't a Cadence Mac connection link.")}
        let items=parts.queryItems ?? [];func value(_ key:String)->String{items.first{$0.name==key}?.value ?? ""}
        guard let port=UInt16(value("port")) else{throw CadenceError.message("Invalid Mac port.")}
        return try Self(id:value("id"),name:value("name"),host:value("host"),port:port)
    }
}
public struct MacRemoteStatus:Codable,Sendable {
    public var playback:PhonePlayback?
    public var deviceName:String?
    public var connected:Bool
    public var message:String?
    public var checkedAt:Date
    public init(playback:PhonePlayback?=nil,deviceName:String?=nil,connected:Bool=false,message:String?=nil,checkedAt:Date=Date()){
        self.playback=playback;self.deviceName=deviceName;self.connected=connected;self.message=message;self.checkedAt=checkedAt
    }
}
public struct MacRemoteRequest:Codable,Sendable {
    public var version=1
    public var id:String
    public var date:Date
    public var command:PhoneCommand?
    public var transfer:PlaybackTransfer?
    public var clientID:String?
    public var acceptsHandoff:Bool?
    public var phonePlayback:PhonePlayback?
    public var acknowledgedInstruction:String?
    public init(command:PhoneCommand?=nil,id:String=UUID().uuidString,date:Date=Date()){self.id=id;self.date=date;self.command=command}
    public func validate(now:Date=Date())throws{
        guard version==1,UUID(uuidString:id) != nil,abs(now.timeIntervalSince(date))<=30 else{throw CadenceError.message("The Mac request expired. Try again.")};try command?.validate();try transfer?.validate();guard command==nil || transfer==nil else{throw CadenceError.message("Conflicting device operations.")}
    }
}
public struct MacRemoteResponse:Codable,Sendable {
    public var id:String
    public var date:Date
    public var playback:PhonePlayback?
    public var error:String?
    public var capabilities:[String]?
    public var transfer:TransferredPlayback?
    public var instruction:PhoneInstruction?
    public var lastTransferID:String?
    public init(id:String,playback:PhonePlayback?=nil,error:String?=nil,date:Date=Date()){self.id=id;self.playback=playback;self.error=error;self.date=date}
    public func validate(requestID:String,now:Date=Date())throws {
        guard id==requestID,abs(now.timeIntervalSince(date))<=30 else{throw CadenceError.message("An outdated Mac reply was ignored.")}
    }
}
public enum MacRemoteCrypto {
    private static let context=Data("Cadence private Mac remote v1".utf8)
    public static func key(_ credentials:ServerCredentials)->SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial:SymmetricKey(data:Data(credentials.password.utf8)),salt:Data(credentials.accountKey.utf8),info:context,outputByteCount:32)
    }
    public static func seal<T:Encodable>(_ value:T,key:SymmetricKey,maximum:Int=60_000)throws->Data{
        let data=try JSONEncoder().encode(value)
        guard data.count<=maximum else{throw CadenceError.message("The remote message is too large.")}
        return try ChaChaPoly.seal(data,using:key,authenticating:context).combined
    }
    public static func open<T:Decodable>(_ type:T.Type,data:Data,key:SymmetricKey,maximum:Int=60_100)throws->T {
        guard data.count<=maximum else{throw CadenceError.message("The remote message is too large.")}
        return try JSONDecoder().decode(type,from:ChaChaPoly.open(ChaChaPoly.SealedBox(combined:data),using:key,authenticating:context))
    }
}
/// The actual command result is cached: retries cannot repeat next/previous or seek.
public struct MacRemoteReplayGuard {
    private var replies:[String:MacRemoteResponse]=[:]
    private var transfers:[String:MacRemoteResponse]=[:]
    public init(){}
    public mutating func executeTransfer(_ request:MacRemoteRequest,now:Date=Date(),action:()throws->MacRemoteResponse)throws->MacRemoteResponse {
        try request.validate(now:now);guard request.transfer != nil else{throw CadenceError.message("Missing transfer.")}
        transfers=transfers.filter{now.timeIntervalSince($0.value.date)<60}
        if var cached=transfers[request.id]{cached.date=now;return cached}
        guard transfers.count<20 else{throw CadenceError.message("Too many device transfers. Wait a moment and retry.")}
        let response:MacRemoteResponse
        do{response=try action()}catch{response=MacRemoteResponse(id:request.id,error:error.localizedDescription,date:now)}
        transfers[request.id]=response;return response
    }
    public mutating func execute(_ request:MacRemoteRequest,now:Date=Date(),action:()throws->PhonePlayback)throws->MacRemoteResponse{
        try request.validate(now:now)
        replies=replies.filter{now.timeIntervalSince($0.value.date)<60}
        if let old=replies[request.id]{return old}
        // Also deduplicate the command UUID across a transport retry with a new request UUID.
        let commandKey=request.command.map{"command:"+$0.id}
        if let commandKey,let old=replies[commandKey]{return MacRemoteResponse(id:request.id,playback:old.playback,error:old.error,date:now)}
        guard replies.count<500 else{throw CadenceError.message("Too many remote commands. Try again in a moment.")}
        let response:MacRemoteResponse
        do{response=MacRemoteResponse(id:request.id,playback:try action(),date:now)}catch{response=MacRemoteResponse(id:request.id,error:error.localizedDescription,date:now)}
        replies[request.id]=response;if let commandKey{replies[commandKey]=response};return response
    }
}

public enum CompanionControlMessage {
    // Mac keys intentionally differ: older iPhone apps must never route a Mac command to their own player.
    public static func stateRequest(mac:Bool)->[String:Any]{[mac ? "requestMacPlayback" : "requestPlayback":true,"target":mac ? "mac" : "phone"]}
    public static func command(_ command:PhoneCommand,mac:Bool)throws->[String:Any]{try command.validate();return [mac ? "macCommand" : "command":try JSONEncoder().encode(command),"target":mac ? "mac" : "phone"]}
}
