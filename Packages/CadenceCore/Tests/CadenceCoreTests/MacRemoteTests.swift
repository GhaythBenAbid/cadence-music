import XCTest
import CadenceCore

final class MacRemoteTests:XCTestCase {
    private func credentials(_ password:String="fixture")->ServerCredentials{.init(server:URL(string:"https://music.example")!,username:"listener",password:password)}
    func testMacMessagesCannotTriggerAnOlderPhonePlayer()throws{
        let message=try CompanionControlMessage.command(PhoneCommand(.next),mac:true)
        XCTAssertNil(message["command"]);XCTAssertNotNil(message["macCommand"])
        let request=CompanionControlMessage.stateRequest(mac:true)
        XCTAssertNil(request["requestPlayback"]);XCTAssertEqual(request["requestMacPlayback"] as? Bool,true)
        XCTAssertNotNil(try CompanionControlMessage.command(PhoneCommand(.pause),mac:false)["command"])
    }
    func testPrivateEndpointValidationAndDeepLink()throws{
        let endpoint=try MacEndpoint(id:UUID().uuidString,name:"My Mac",host:"100.100.10.10")
        XCTAssertEqual(try MacEndpoint.from(endpoint.connectionURL),endpoint)
        for host in ["127.0.0.1","0.0.0.0","192.168.1.2","8.8.8.8","100.63.0.1","100.128.0.1","100.064.0.1","100.100.10.10.evil"]{XCTAssertFalse(MacEndpoint.isTailnetAddress(host));XCTAssertThrowsError(try MacEndpoint(id:UUID().uuidString,name:"Mac",host:host))}
        var value=endpoint;value.host="8.8.8.8"
        XCTAssertThrowsError(try JSONDecoder().decode(MacEndpoint.self,from:JSONEncoder().encode(value)))
    }
    func testEncryptedMessageRejectsTamperingAndOtherAccounts()throws{
        let request=MacRemoteRequest(command:PhoneCommand(.next)),key=MacRemoteCrypto.key(credentials())
        let sealed=try MacRemoteCrypto.seal(request,key:key)
        XCTAssertEqual(try MacRemoteCrypto.open(MacRemoteRequest.self,data:sealed,key:key).id,request.id)
        XCTAssertThrowsError(try MacRemoteCrypto.open(MacRemoteRequest.self,data:sealed,key:MacRemoteCrypto.key(credentials("wrong"))))
        var changed=sealed;changed[changed.count/2] ^= 1
        XCTAssertThrowsError(try MacRemoteCrypto.open(MacRemoteRequest.self,data:changed,key:key))
        let other=ServerCredentials(server:URL(string:"https://music.example")!,username:"other",password:"fixture")
        XCTAssertThrowsError(try MacRemoteCrypto.open(MacRemoteRequest.self,data:sealed,key:MacRemoteCrypto.key(other)))
    }
    func testFreshnessAndResponseCorrelation()throws{
        let now=Date(),request=MacRemoteRequest(date:Date().addingTimeInterval(-31))
        XCTAssertThrowsError(try request.validate(now:now))
        XCTAssertThrowsError(try MacRemoteResponse(id:"old").validate(requestID:"new"))
        XCTAssertThrowsError(try MacRemoteCrypto.open(MacRemoteRequest.self,data:Data(repeating:0,count:60_101),key:MacRemoteCrypto.key(credentials())))
    }
    func testTransportAndCommandRetriesExecuteOnce()throws{
        var replay=MacRemoteReplayGuard(),calls=0
        let command=PhoneCommand(.next),first=MacRemoteRequest(command:command)
        let action={calls+=1;return PhonePlayback(song:nil,isPlaying:false,elapsed:0,duration:0,shuffled:false,repeats:false,volume:1)}
        _=try replay.execute(first,action:action);_=try replay.execute(first,action:action)
        let second=MacRemoteRequest(command:command)
        XCTAssertEqual(try replay.execute(second,action:action).id,second.id)
        XCTAssertEqual(calls,1)
    }
}
