import AppKit
import CoreGraphics
import PrivateApi

enum PrivateFrameVerdict: Equatable {
    case inconclusive(String)
    case failed(String)
    case verified
}

func comparePrivateWindowFrame(_ privateFrame: CGRect?, publicFrame: CGRect?) -> PrivateFrameVerdict {
    guard let publicFrame else { return .inconclusive("no public window-list witness") }
    guard let privateFrame else { return .failed("private frame query returned no frame") }
    let agrees = abs(privateFrame.minX - publicFrame.minX) <= 1
        && abs(privateFrame.minY - publicFrame.minY) <= 1
        && abs(privateFrame.width - publicFrame.width) <= 1
        && abs(privateFrame.height - publicFrame.height) <= 1
    return agrees ? .verified : .failed("private frame disagrees with public bounds")
}
