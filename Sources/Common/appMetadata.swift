public let stableWinMuxAppId: String = "com.gfavaro.stripmuxx"
public let forkRepositoryURL = "https://github.com/gfavaro/StripMuxX"
public let winMuxAppSupportDirectoryName = "StripMuxX"
#if DEBUG
    public let winMuxAppId: String = "com.gfavaro.stripmuxx.debug"
    public let winMuxAppName: String = "StripMuxX-Debug"
#else
    public let winMuxAppId: String = stableWinMuxAppId
    public let winMuxAppName: String = "StripMuxX"
#endif
