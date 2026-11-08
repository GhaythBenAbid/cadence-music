import SwiftUI
import WatchKit
@main struct CadenceWatchApp:App{
    @WKApplicationDelegateAdaptor(WatchDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store=WatchStore.shared
    var body:some Scene{WindowGroup{WatchRoot().environmentObject(store).tint(Color(red:0.84,green:0.96,blue:0.4)).preferredColorScheme(.dark).onChange(of:scenePhase){_,phase in if phase != .active{store.audio.persist()}}}}
}
