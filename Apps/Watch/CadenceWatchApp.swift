import SwiftUI
import WatchKit
@main struct CadenceWatchApp:App{
    @WKApplicationDelegateAdaptor(WatchDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store=WatchStore.shared
    var body:some Scene{WindowGroup{rootView.transformEnvironment(\.dynamicTypeSize){size in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--watch-ui-testing"),ProcessInfo.processInfo.arguments.contains("--watch-large-text"){size = .xxxLarge}
                #endif
            }.transformEnvironment(\.isLuminanceReduced){reduced in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--watch-ui-testing"),ProcessInfo.processInfo.arguments.contains("--watch-dimmed"){reduced=true}
                #endif
            }.transformEnvironment(\.scenePhase){phase in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--watch-ui-testing"),ProcessInfo.processInfo.arguments.contains("--watch-dimmed"){phase = .inactive}
                #endif
            }.environmentObject(store).tint(Color(red:0.84,green:0.96,blue:0.4)).preferredColorScheme(.dark).onChange(of:scenePhase){_,phase in if phase != .active{store.audio.persist()}}}}
    @ViewBuilder private var rootView:some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--watch-ui-testing"),ProcessInfo.processInfo.arguments.contains("--watch-lifecycle-fixture"){WatchLifecycleFixture()}else if ProcessInfo.processInfo.arguments.contains("--watch-ui-testing"),ProcessInfo.processInfo.arguments.contains("--remote-volume-fixture"){WatchRemoteVolumeFixture()}else{WatchRoot()}
        #else
        WatchRoot()
        #endif
    }

}

#if DEBUG
private struct WatchLifecycleFixture:View {
    @State private var step=0
    var body:some View {
        WatchRoot().environment(\.scenePhase,step==1 ? .inactive : .active)
            .environment(\.isLuminanceReduced,step != 0)
            .overlay(alignment:.bottomLeading){Button("Phone event"){WatchDelegate().handleRemoteNowPlayingActivity()}.font(.caption2).buttonStyle(.plain).padding(5).background(.black,in:Capsule()).accessibilityIdentifier("watch.fixture.phone-event")}
            .overlay(alignment:.bottomTrailing){
                Button(step==0 ? "Lower wrist" : step==1 ? "Raise wrist" : "Finish wake"){step=(step+1)%3}
                    .font(.caption2).buttonStyle(.plain).padding(5).background(.black,in:Capsule())
                    .accessibilityIdentifier("watch.fixture.lifecycle")
            }
    }
}
#endif
