import Foundation

public enum SearchKind:String,CaseIterable,Identifiable,Sendable {
    case songs="Songs",artists="Artists",albums="Albums"
    public var id:String{rawValue}
    public func count(_ result:SearchResults)->Int{switch self{case .songs:return result.song?.count ?? 0;case .artists:return result.artist?.count ?? 0;case .albums:return result.album?.count ?? 0}}
    public func parameters(offset:Int,size:Int)->[URLQueryItem]{
        let count=max(1,min(size,100)),offset=max(0,offset)
        let selected:String
        switch self{case .songs:selected="song";case .artists:selected="artist";case .albums:selected="album"}
        var result:[URLQueryItem]=[]
        for kind in ["song","artist","album"]{
            result.append(URLQueryItem(name:kind+"Count",value:String(kind==selected ? count : 0)))
            result.append(URLQueryItem(name:kind+"Offset",value:String(offset)))
        }
        return result
    }
}
