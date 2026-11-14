@testable import AppBundle
import Common
import Foundation
import TOMLKit

extension [TomlParseError] {
    var descriptions: [String] { map(\.description) }
}

extension FocusCommand {
    static func new(direction: CardinalDirection) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], targetArg: .direction(direction)))
    }
    static func new(dfsRelative: DfsNextPrev) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], targetArg: .dfsRelative(dfsRelative)))
    }
}
