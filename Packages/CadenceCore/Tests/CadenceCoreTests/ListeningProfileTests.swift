import XCTest
@testable import CadenceCore
final class ListeningProfileTests:XCTestCase {
    func testHistoryMergesProgressAndSeparatesAccounts()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=ListeningProfileStore(root:root);var profile=ListeningProfile();let song=Song(id:"s",title:"Song",artist:"Artist")
        profile.record(ListeningEntry(id:"session",song:song,seconds:12,position:12));profile.record(ListeningEntry(id:"session",song:song,seconds:20,position:19,skipped:true));XCTAssertEqual(profile.history.count,1);XCTAssertEqual(profile.history[0].seconds,20);XCTAssertTrue(profile.history[0].skipped)
        store.save(profile,account:"one");XCTAssertEqual(store.load("one").history.count,1);XCTAssertTrue(store.load("two").history.isEmpty)
        store.clear("one");XCTAssertTrue(store.load("one").history.isEmpty)
    }
    func testRecommendationsUseFollowsListeningSkipsAndUniquePlayableCandidates(){
        var profile=ListeningProfile();let loved=Song(id:"l",title:"Loved",artist:"Loved artist"),next=Song(id:"n",title:"Next",artist:"Loved artist"),other=Song(id:"o",title:"Other",artist:"Other artist")
        profile.follow(MusicCatalogEntry(id:"artist",kind:.artist,title:"Loved artist",artist:"Loved artist"))
        XCTAssertEqual(profile.recommendations(candidates:[next,other,next],favorites:[]).map(\.id),[next.id,other.id])
        for i in 0..<4{profile.record(ListeningEntry(id:String(i),song:next,seconds:2,position:2,skipped:true))}
        XCTAssertEqual(profile.recommendations(candidates:[next,other],favorites:[],seed:loved).first?.id,other.id)
        XCTAssertFalse(profile.recommendations(candidates:[loved,next],favorites:[loved],seed:loved).contains{$0.id==loved.id})
    }
}
