import SwiftUI
@main struct CadenceApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store=PhoneStore.shared
    var body:some Scene { WindowGroup { PhoneRoot().environmentObject(store).tint(Palette.ink).preferredColorScheme(.light).task(id:scenePhase){guard scenePhase == .active else{return};while !Task.isCancelled{await store.pollPlaybackDevice();do{try await Task.sleep(for:.seconds(2))}catch{return}}}.task{while !Task.isCancelled{await store.globalPlayback.sync();do{try await Task.sleep(for:.seconds(3))}catch{return}}}.onOpenURL{store.connectMac($0)}.onChange(of:scenePhase){_,phase in if phase != .active{store.audio.persist()}} } }
}
