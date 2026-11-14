import Common
import TOMLKit

// WinMux-family configs can set virtual workspaces, Dwindle, Master, tab groups, a sidebar
// and more, which StripMuxX does not have. Such a config still loads: what it sets for them is skipped,
// and `doctor` lists it, instead of the whole file being rejected.

/// Root keys of removed features.
let removedRootConfigKeys: Set<String> = [
    "after-login-command", "animations", "auto-add-new-windows-to-tab-group", "automatically-unhide-macos-hidden-apps",
    "borders", "default-root-container-layout", "default-root-container-orientation", "dimming", "drag-stack-layout",
    "enable-normalization-flatten-containers", "enable-normalization-opposite-orientation-for-nested-containers",
    "enable-shake-to-toggle-tiling", "focus-follows-mouse", "focus-follows-mouse-dwell", "follow-app-activation",
    "hover-bar", "indent-for-nested-containers-with-the-same-orientation", "master",
    "non-empty-workspaces-root-containers-layout-on-startup", "on-display-changed", "shortcuts-preset",
    "start-workspaces-on-main-monitor", "tab-group-padding", "window-tabs", "workspace", "workspace-backend",
    "workspace-overview", "workspace-sidebar", "workspace-swipe",
]

/// Keys of kept tables whose features were removed.
let removedTableConfigKeys: [String: Set<String>] = [
    "native-spaces": ["tiling-enabled"],
]

/// Commands of removed features.
let removedCommandNames: Set<String> = [
    "agent", "move-node-to-project", "no-peek", "open-sidebar", "palette", "project", "split", "stack-with",
    "state", "subscribe", "summon-workspace", "swap-with-master", "workspace-layout", "workspace-overview",
]

/// Whether a command line calls a removed command, or a removed form of a kept one:
/// container layouts and tab focus.
func isRemovedCommandScript(_ script: String) -> Bool {
    let words = script.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let name = words.first else { return false }
    if removedCommandNames.contains(name) { return true }
    let args = words.dropFirst()
    switch name {
        case "layout":
            return args.contains { !$0.hasPrefix("-") && $0 != "tiling" && $0 != "floating" && UInt32($0) == nil }
        case "focus":
            return args.contains { $0 == "tab-next" || $0 == "tab-prev" || $0 == "--tab-index" }
        default:
            return false
    }
}

/// The command lines a binding, hook or rule value holds.
func commandScripts(_ raw: TOMLValueConvertible) -> [String] {
    if let string = raw.string { return [string] }
    guard let array = raw.array else { return [] }
    return (0 ..< array.count).compactMap { array[$0].string }
}

/// What a config sets for removed features, as key paths, for `doctor`.
func removedConfiguration(in table: TOMLTable) -> [String] {
    var result = table.keys.filter(removedRootConfigKeys.contains).sorted()
    for (tableName, keys) in removedTableConfigKeys.sorted(by: { $0.key < $1.key }) {
        guard let nested = table[tableName]?.table else { continue }
        result += nested.keys.filter(keys.contains).sorted().map { "\(tableName).\($0)" }
    }
    if let modes = table["mode"]?.table {
        for modeName in modes.keys.sorted() {
            guard let bindings = modes[modeName]?.table?["binding"]?.table else { continue }
            for binding in bindings.keys.sorted() {
                for script in commandScripts(bindings[binding]!) where isRemovedCommandScript(script) {
                    result.append("mode.\(modeName).binding.\(binding) = '\(script)'")
                }
            }
        }
    }
    return result
}
