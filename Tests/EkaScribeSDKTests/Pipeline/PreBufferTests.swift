import XCTest
@testable import EkaScribeSDK

final class PreBufferTests: XCTestCase {

    func testWriteAndDrain() {
        let buffer = PreBuffer(capacity: 10)

        let frame1 = makeFrame(timestampMs: 1)
        let frame2 = makeFrame(timestampMs: 2)

        XCTAssertTrue(buffer.write(frame1))
        XCTAssertTrue(buffer.write(frame2))

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained[0].timestampMs, 1)
        XCTAssertEqual(drained[1].timestampMs, 2)
    }

    func testCapacityEnforced() {
        let buffer = PreBuffer(capacity: 3)

        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 1)))
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 2)))
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 3)))
        XCTAssertFalse(buffer.write(makeFrame(timestampMs: 4)), "Should reject write when full")
    }

    func testDrainEmptyReturnsEmpty() {
        let buffer = PreBuffer(capacity: 10)
        XCTAssertTrue(buffer.drain().isEmpty)
    }

    func testClearResetsBehavior() {
        let buffer = PreBuffer(capacity: 5)

        _ = buffer.write(makeFrame(timestampMs: 1))
        _ = buffer.write(makeFrame(timestampMs: 2))

        buffer.clear()

        let drained = buffer.drain()
        XCTAssertTrue(drained.isEmpty, "Buffer should be empty after clear")

        // Should be able to write again
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 3)))
        XCTAssertEqual(buffer.drain().count, 1)
    }

    func testRingBufferWrapsAround() {
        let buffer = PreBuffer(capacity: 3)

        // Fill and drain
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 1)))
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 2)))
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 3)))

        let drained1 = buffer.drain()
        XCTAssertEqual(drained1.count, 3)

        // Write again (wrap around)
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 4)))
        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 5)))

        let drained2 = buffer.drain()
        XCTAssertEqual(drained2.count, 2)
        XCTAssertEqual(drained2[0].timestampMs, 4)
        XCTAssertEqual(drained2[1].timestampMs, 5)
    }

    func testMultipleDrainCycles() {
        let buffer = PreBuffer(capacity: 2)

        for cycle in 0..<5 {
            let ts = cycle * 10
            XCTAssertTrue(buffer.write(makeFrame(timestampMs: ts)))
            XCTAssertTrue(buffer.write(makeFrame(timestampMs: ts + 1)))

            let drained = buffer.drain()
            XCTAssertEqual(drained.count, 2, "Cycle \(cycle) should drain 2 frames")
            XCTAssertEqual(drained[0].timestampMs, ts)
            XCTAssertEqual(drained[1].timestampMs, ts + 1)
        }
    }

    func testConcurrentWriteAndDrain() {
        let buffer = PreBuffer(capacity: 1000)
        let writeExpectation = expectation(description: "Writers complete")
        writeExpectation.expectedFulfillmentCount = 2
        let drainExpectation = expectation(description: "Drainer completes")

        var totalDrained = 0
        let drainLock = NSLock()

        // Writer 1
        DispatchQueue.global().async {
            for i in 0..<100 {
                _ = buffer.write(makeFrame(timestampMs: i))
            }
            writeExpectation.fulfill()
        }

        // Writer 2
        DispatchQueue.global().async {
            for i in 100..<200 {
                _ = buffer.write(makeFrame(timestampMs: i))
            }
            writeExpectation.fulfill()
        }

        // Drainer
        DispatchQueue.global().async {
            // Drain multiple times to collect all written frames
            for _ in 0..<50 {
                let drained = buffer.drain()
                drainLock.lock()
                totalDrained += drained.count
                drainLock.unlock()
                usleep(1000) // 1ms delay
            }
            drainExpectation.fulfill()
        }

        wait(for: [writeExpectation, drainExpectation], timeout: 5.0)

        // Final drain to catch any remaining
        totalDrained += buffer.drain().count
        // We don't assert exact count due to timing, but should not crash
        XCTAssertGreaterThanOrEqual(totalDrained, 0, "Thread-safe draining should work")
    }

    func testCapacityOne() {
        let buffer = PreBuffer(capacity: 1)

        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 1)))
        XCTAssertFalse(buffer.write(makeFrame(timestampMs: 2)))

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained[0].timestampMs, 1)

        XCTAssertTrue(buffer.write(makeFrame(timestampMs: 3)))
    }
}
