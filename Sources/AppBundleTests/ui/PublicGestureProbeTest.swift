@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class PublicGestureProbeTest: XCTestCase {
    func testDisabledProbeDoesNotRecordEvents() {
        let probe = PublicGestureProbe()
        probe.observeCGScroll(.init(deltaX: -100, deltaY: 0, isContinuous: true,
                                    optionOnly: false, phase: 1, momentumPhase: 0, point: .zero))
        XCTAssertEqual(probe.counters.cgScrollTotal, 0)
    }

    func testOutputDoesNotPretendToClassifyFingerCount() {
        let probe = PublicGestureProbe()
        let report = probe.report(elapsed: 0)
        XCTAssertTrue(report.contains("CANNOT distinguish two from three fingers"))
        XCTAssertTrue(report.contains("No touch data was captured"))
    }
}
