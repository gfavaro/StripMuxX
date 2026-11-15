import AppKit
import Darwin

extension NSRunningApplication {
    /// When the process started. AppKit leaves `launchDate` nil for processes launchd starts
    /// directly, such as Finder; the kernel's start time identifies those just as well.
    public var processLaunchDate: Date? {
        if let launchDate { return launchDate }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
