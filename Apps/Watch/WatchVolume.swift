import SwiftUI
import WatchKit

struct WatchVolume:WKInterfaceObjectRepresentable {
    var active:Bool
    final class Coordinator {
        var requested:Bool?
        var pending:DispatchWorkItem?
        func update(_ object:WKInterfaceVolumeControl,active:Bool){
            guard requested != active else{return}
            requested=active;pending?.cancel()
            if active{
                // WatchKit needs its control attached before accepting Crown focus.
                let work=DispatchWorkItem{[weak self,weak object] in guard self?.requested==true else{return};object?.focus()}
                pending=work;DispatchQueue.main.async(execute:work)
            }else{object.resignFocus()}
        }
    }
    func makeCoordinator()->Coordinator{Coordinator()}
    func makeWKInterfaceObject(context:Context)->WKInterfaceVolumeControl{WKInterfaceVolumeControl(origin:.local)}
    func updateWKInterfaceObject(_ object:WKInterfaceVolumeControl,context:Context){context.coordinator.update(object,active:active)}
    static func dismantleWKInterfaceObject(_ object:WKInterfaceVolumeControl,coordinator:Coordinator){coordinator.pending?.cancel();coordinator.requested=false;object.resignFocus()}
}

