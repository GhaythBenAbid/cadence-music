import SwiftUI
import AppKit

struct MacPlaybackKeys:NSViewRepresentable {
    var toggle:()->Void
    func makeNSView(context:Context)->KeyView{let view=KeyView();view.toggle=toggle;return view}
    func updateNSView(_ view:KeyView,context:Context){view.toggle=toggle}
    static func dismantleNSView(_ view:KeyView,coordinator:()){view.stop()}
    static func handlesSpace(keyCode:UInt16,repeated:Bool,modifiers:NSEvent.ModifierFlags,editing:Bool,modal:Bool)->Bool{
        keyCode==49 && !repeated && modifiers.intersection([.command,.option,.control,.shift]).isEmpty && !editing && !modal
    }
    final class KeyView:NSView {
        var toggle:(()->Void)?
        private var monitor:Any?
        override func hitTest(_ point:NSPoint)->NSView?{nil}
        override func viewDidMoveToWindow(){super.viewDidMoveToWindow();stop();guard window != nil else{return}
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
                guard let self,let window=self.window,event.window===window,NSApp.isActive else{return event}
                let responder=window.firstResponder
                let editing=(responder as? NSTextView)?.isEditable==true || responder is NSTextField
                let modal=window.attachedSheet != nil || window.sheetParent != nil || NSApp.modalWindow != nil
                guard MacPlaybackKeys.handlesSpace(keyCode:event.keyCode,repeated:event.isARepeat,modifiers:event.modifierFlags,editing:editing,modal:modal) else{return event}
                self.toggle?();return nil
            }
        }
        func stop(){if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil}
    }
}
