import Common
import Foundation

let generatedConfigDirectoryName = "stripmuxx"
let generatedConfigFileName = "stripmuxx.toml"

func xdgConfigHomeUrl() -> URL {
    ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
}

func generatedConfigUrl() -> URL {
    xdgConfigHomeUrl()
        .appending(path: generatedConfigDirectoryName)
        .appending(path: generatedConfigFileName)
}

@MainActor
func preferredEditableConfigUrl() -> URL {
    if let configLocation = serverArgs.configLocation {
        return URL(filePath: configLocation)
    }
    if let customConfigUrl = findCustomConfigUrl().urlOrNil {
        return customConfigUrl
    }
    return generatedConfigUrl()
}

/// A new user's config: the reference configuration, bindings included.
func starterConfigText() -> String {
    (try? String(contentsOf: defaultConfigUrl, encoding: .utf8)) ?? """
        config-version = 2

        [mode.main.binding]
        """
}

/// StripMuxX's own config file. It is never imported from another window manager:
/// a missing file is created from the reference configuration.
@MainActor
func ensureBootstrapConfigExistsIfNeeded() throws -> URL? {
    guard serverArgs.configLocation == nil else { return nil }
    let targetUrl = generatedConfigUrl()
    return try materializeBootstrapConfigIfNeeded(targetUrl: targetUrl) ? targetUrl : nil
}

@MainActor
func materializeBootstrapConfigIfNeeded(targetUrl: URL) throws -> Bool {
    guard !FileManager.default.fileExists(atPath: targetUrl.path) else { return false }
    let parentUrl = targetUrl.deletingLastPathComponent()
    if parentUrl.path != targetUrl.path {
        try FileManager.default.createDirectory(at: parentUrl, withIntermediateDirectories: true)
    }
    try ConfigFileStore.installBootstrap(starterConfigText(), at: targetUrl)
    return true
}

func findCustomConfigUrl() -> ConfigFile {
    let candidates: [URL] = if let configLocation = serverArgs.configLocation {
        [URL(filePath: configLocation)]
    } else {
        [generatedConfigUrl()]
    }
    let existingCandidates: [URL] = candidates.filter { (candidate: URL) in FileManager.default.fileExists(atPath: candidate.path) }
    let count = existingCandidates.count
    return switch count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates.first.orDie())
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
