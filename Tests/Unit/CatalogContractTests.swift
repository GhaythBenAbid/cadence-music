import XCTest
import CadenceCore
@testable import Cadence

@MainActor final class CatalogContractTests:XCTestCase {
    func testSearchOffsetsAdvanceByServerRowsAndPreserveDuplicatesAcrossPages()async{
        let state=CatalogSearchState();let first=(0..<30).map{Song(id:String($0),title:"Song \($0)")}
        var requested:[Int]=[]
        await state.load(query:"Song",kind:.songs,fetch:{_,_,offset in requested.append(offset);return SearchResults(song:first)})
        XCTAssertTrue(state.hasMore)
        await state.load(query:"Song",kind:.songs,fetch:{_,_,offset in requested.append(offset);return SearchResults(song:[first[0],Song(id:"30",title:"More")])})
        XCTAssertEqual(requested,[0,30]);XCTAssertEqual(state.songs.count,31);XCTAssertFalse(state.hasMore)
    }
    func testAStalePageCannotPopulateANewerSearch()async{
        let state=CatalogSearchState()
        var continuation:CheckedContinuation<SearchResults,Never>?
        let old=Task{await state.load(query:"old",kind:.songs,fetch:{_,_,_ in await withCheckedContinuation{continuation=$0}})}
        for _ in 0..<20 where continuation==nil{await Task.yield()}
        state.reset()
        await state.load(query:"new",kind:.songs,fetch:{_,_,_ in SearchResults(song:[Song(id:"new",title:"New")])})
        continuation?.resume(returning:SearchResults(song:[Song(id:"old",title:"Old")]))
        await old.value;XCTAssertEqual(state.songs.map(\.id),["new"]);XCTAssertFalse(state.loading)
    }
    func testOptionalLiveSearchPagingAndArtistAlbums()async throws{
        struct Fixture:Decodable{var url:String;var username:String;var password:String}
        let file=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CadenceLiveSearchFixture.json")
        guard let data=try? Data(contentsOf:file) else{throw XCTSkip("Requires a private live search fixture.")};try FileManager.default.removeItem(at:file)
        let fixture=try JSONDecoder().decode(Fixture.self,from:data),api=SubsonicAPI(credentials:ServerCredentials(server:try ServerCredentials.normalizedServer(fixture.url),username:fixture.username,password:fixture.password))
        for kind in SearchKind.allCases{
            let first=try await api.search("a",kind:kind,offset:0,size:1)
            let next=try await api.search("a",kind:kind,offset:1,size:1)
            XCTAssertEqual(kind.count(first),1);XCTAssertEqual(kind.count(next),1)
            switch kind{
            case .songs:XCTAssertNotEqual(first.song?.first?.id,next.song?.first?.id)
            case .artists:let id=try XCTUnwrap(first.artist?.first?.id);XCTAssertNotEqual(id,next.artist?.first?.id);let artist=try await api.artist(id);XCTAssertNotNil(artist.album)
            case .albums:XCTAssertNotEqual(first.album?.first?.id,next.album?.first?.id)
            }
        }
        let first=try await api.albums(offset:0,size:1),next=try await api.albums(offset:1,size:1)
        XCTAssertEqual(first.count,1);XCTAssertEqual(next.count,1);XCTAssertNotEqual(first.first?.id,next.first?.id)
    }
}
