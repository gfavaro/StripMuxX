@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class GestureTraceTest: XCTestCase {
    func testATraceThatStopsByItselfKeepsItsRecording() async throws {
        let io = CmdIo(stdin: .emptyStdin)
        XCTAssertTrue(GestureTrace.shared.start(io: io, stopsAfter: .milliseconds(60)))
        GestureTrace.shared.note("pan", delta: 4, from: 0, offset: 4)
        GestureTrace.shared.note("end", offset: 4)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(GestureTrace.shared.running, "The limit stopped it")

        let collect = CmdIo(stdin: .emptyStdin)
        XCTAssertTrue(GestureTrace.shared.stop(io: collect), "Stopping after the limit hands back the recording")
        let report = try XCTUnwrap(collect.stdout.first)
        let path = String(try XCTUnwrap(report.split(separator: "\n").first))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(report.contains("2 input steps"), report)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        XCTAssertEqual((json["inputs"] as? [Any])?.count, 2)

        let again = CmdIo(stdin: .emptyStdin)
        XCTAssertFalse(GestureTrace.shared.stop(io: again), "It is handed back once")
        XCTAssertEqual(again.stderr, ["No gesture trace is running"])
    }

    func testStoppingATraceInTimeStillWorksAndTheLimitDoesNotFireTwice() async throws {
        let io = CmdIo(stdin: .emptyStdin)
        XCTAssertTrue(GestureTrace.shared.start(io: io, stopsAfter: .milliseconds(200)))
        GestureTrace.shared.note("dock", delta: 10, from: 0, offset: 10)
        let stop = CmdIo(stdin: .emptyStdin)
        XCTAssertTrue(GestureTrace.shared.stop(io: stop))
        let path = String(try XCTUnwrap(stop.stdout.first?.split(separator: "\n").first))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(try XCTUnwrap(stop.stdout.first).contains("1 input steps"))
        try await Task.sleep(for: .milliseconds(500))
        let late = CmdIo(stdin: .emptyStdin)
        XCTAssertFalse(GestureTrace.shared.stop(io: late), "Nothing was kept from the cancelled limit")
    }
}
