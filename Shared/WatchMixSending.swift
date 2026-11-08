import Foundation
import CadenceCore

@MainActor protocol WatchMixSending:AnyObject {
    var canTransfer:Bool{get}
    var supportsMultipleMixes:Bool{get}
    func receipt(for mix:RunMix)->WatchReceipt?
    var receipt:WatchReceipt?{get}
    func sendMix(_ mix:RunMix)throws
    func sendFile(_ file:URL,payload:TrackTransfer)throws
    func cancelOutstanding()
    func resetReceipt()
    func outstandingSongIDs(for mix:RunMix)->Set<String>
}

extension WatchMixSending {
    var supportsMultipleMixes:Bool{false}
    func receipt(for mix:RunMix)->WatchReceipt?{guard let receipt,receipt.mixID==mix.id,receipt.accountKey==mix.accountKey else{return nil};return receipt}
}
