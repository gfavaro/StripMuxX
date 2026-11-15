import Foundation
import MachO

/// The commit a release was built from. Release builds link it into the binary's
/// `__TEXT,__smx_build` section (`script/fork-build.sh`), so no source file changes per
/// build; debug and test builds have no section and report SNAPSHOT.
public let gitHash: String = buildInfoLines.first ?? "SNAPSHOT"
public let gitShortHash: String = buildInfoLines.dropFirst().first ?? "SNAPSHOT"

private let buildInfoLines: [String] = {
    var size: UInt = 0
    let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
    guard let data = getsectiondata(header, "__TEXT", "__smx_build", &size), size > 0 else { return [] }
    let text = String(decoding: UnsafeBufferPointer(start: data, count: Int(size)), as: UTF8.self)
    return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
}()
