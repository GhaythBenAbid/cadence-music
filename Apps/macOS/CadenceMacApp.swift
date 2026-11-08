import SwiftUI
import CadenceCore
@main struct CadenceMacApp:App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store=MacStore()
    var body:some Scene {
        WindowGroup("Cadence"){MacRoot().background(MacPlaybackKeys{store.togglePlayback()}).environmentObject(store).tint(MacPalette.ink).preferredColorScheme(.light).frame(minWidth:900,minHeight:640).task{while !Task.isCancelled{await store.globalPlayback.sync();do{try await Task.sleep(for:.seconds(3))}catch{return}}}.onChange(of:scenePhase){_,phase in if phase != .active{store.audio.persist()}}}
        .defaultSize(width:1200,height:800)
        .commands{
            CommandGroup(after:.newItem){Button("Refresh library"){Task{await store.refresh()}}.keyboardShortcut("r")}
            CommandMenu("Playback"){
                Button((store.remote.playingOnPhone ? store.remote.phonePlayback?.isPlaying==true : store.audio.isPlaying) ? "Pause" : "Play"){store.togglePlayback()}
                Button("Next track"){store.deviceCommand(PhoneCommand(.next))}.keyboardShortcut(.rightArrow,modifiers:.command)
                Button("Previous track"){store.deviceCommand(PhoneCommand(.previous))}.keyboardShortcut(.leftArrow,modifiers:.command)
            }
        }
        Settings{MacAccountView().environmentObject(store).frame(width:460).padding(28)}
    }
}
