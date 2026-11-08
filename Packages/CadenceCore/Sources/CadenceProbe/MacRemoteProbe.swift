#if os(macOS)
import Foundation
import CadenceCore

@MainActor enum MacRemoteProbe {
    static func run()async throws{
        let suite="CadenceRemoteProbe-"+UUID().uuidString,preferences=UserDefaults(suiteName:suite)!
        defer{UserDefaults.standard.removePersistentDomain(forName:suite)}
        let credentials=ServerCredentials(server:URL(string:"https://fixture.example")!,username:"fixture",password:UUID().uuidString)
        let server=PrivateMacServer(port:47824,preferences:preferences,advertise:false)
        defer{server.stop()}
        var calls=0,state=PhonePlayback(song:Song(id:"one",title:"Original test track"),isPlaying:true,elapsed:1,duration:205,shuffled:false,repeats:true,volume:1)
        server.playback={state}
        server.command={command in
            try command.validate();calls+=1
            switch command.action{
            case .next:state.song=Song(id:"two",title:"Next test track")
            case .pause:state.isPlaying=false
            case .volume:state.volume=command.value ?? 1
            default:break
            };state.updatedAt=Date();return state
        }
        server.configure(credentials)
        for _ in 0..<80 where server.endpoint==nil{try await Task.sleep(for:.milliseconds(50))}
        guard let endpoint=server.endpoint else{throw CadenceError.message("Tailscale server failed to bind: "+server.message)}
        print("PASS: production listener bound to private Tailscale endpoint \(endpoint.host):\(endpoint.port)")
        let client=PrivateMacClient(preferences:preferences);client.configure(credentials);try client.select(endpoint)
        guard try await client.fetch().song?.id=="one" else{throw CadenceError.message("Initial remote state mismatch")}
        let next=PhoneCommand(.next)
        guard try await client.fetch(next).song?.id=="two" else{throw CadenceError.message("Next command wasn't confirmed")}
        _=try await client.fetch(next)
        guard calls==1 else{throw CadenceError.message("A duplicate command executed twice")}
        guard try await client.fetch(PhoneCommand(.pause)).isPlaying==false else{throw CadenceError.message("Pause wasn't confirmed")}
        guard try await client.fetch(PhoneCommand(.volume,value:0.3)).volume==0.3 else{throw CadenceError.message("Volume wasn't confirmed")}
        let before=calls,wrong=PrivateMacClient(preferences:UserDefaults(suiteName:suite+"-wrong")!)
        defer{UserDefaults.standard.removePersistentDomain(forName:suite+"-wrong")}
        wrong.configure(ServerCredentials(server:credentials.server,username:credentials.username,password:"incorrect fixture"));try wrong.select(endpoint)
        var rejected=false
        do{_=try await wrong.fetch(PhoneCommand(.next))}catch{rejected=true}
        guard rejected,calls==before else{throw CadenceError.message("Wrong credentials were not rejected")}
        print("PASS: real encrypted TCP state / next / pause / volume round trips")
        print("PASS: duplicate command executed once; wrong password cannot control playback")
        // Leave the verified production listener briefly visible for an OS-level bind check.
        try await Task.sleep(for:.seconds(5))
    }
}
#endif
