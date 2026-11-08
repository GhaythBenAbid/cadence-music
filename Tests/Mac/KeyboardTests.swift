import XCTest
import AppKit

final class KeyboardTests:XCTestCase {
    func testSpaceTogglesOnlyOutsideEditingAndDialogs(){
        XCTAssertTrue(MacPlaybackKeys.handlesSpace(keyCode:49,repeated:false,modifiers:[],editing:false,modal:false))
        XCTAssertFalse(MacPlaybackKeys.handlesSpace(keyCode:49,repeated:false,modifiers:[],editing:true,modal:false))
        XCTAssertFalse(MacPlaybackKeys.handlesSpace(keyCode:49,repeated:false,modifiers:[],editing:false,modal:true))
        XCTAssertFalse(MacPlaybackKeys.handlesSpace(keyCode:49,repeated:true,modifiers:[],editing:false,modal:false))
        XCTAssertFalse(MacPlaybackKeys.handlesSpace(keyCode:49,repeated:false,modifiers:.command,editing:false,modal:false))
    }
}
