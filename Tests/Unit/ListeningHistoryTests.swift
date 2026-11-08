import XCTest
import CadenceCore
@testable import Cadence

@MainActor final class ListeningHistoryTests:XCTestCase {
    func testAudibleProgressRecordsListeningButSeekingAndBufferingDoNot()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let audio=AudioController(sessions:PlaybackSessionStore(root:root));audio.configureSession(account:"one",resolver:{_ in nil});audio.current=Song(id:"song",title:"Song",duration:100)
        var heard:ListeningEntry?;audio.onListeningEvent={account,event in XCTAssertEqual(account,"one");heard=event}
        audio.sampleListening(position:0,audible:true);audio.sampleListening(position:1,audible:true);audio.sampleListening(position:80,audible:true);audio.sampleListening(position:81,audible:false);audio.sampleListening(position:82,audible:true);audio.sampleListening(position:83,audible:true);audio.flushListening()
        XCTAssertEqual(heard?.seconds,2);audio.stop()
    }
}
