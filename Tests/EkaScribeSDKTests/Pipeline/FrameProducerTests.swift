import XCTest
@testable import EkaScribeSDK

final class FrameProducerTests: XCTestCase {

    func testStartDrainsPreBuffer() async {
        let preBuffer = PreBuffer(capacity: 100)
        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let logger = MockLogger()

        let producer = FrameProducer(preBuffer: preBuffer, continuation: continuation, logger: logger)

        // Write frames before starting
        _ = preBuffer.write(makeFrame(timestampMs: 1))
        _ = preBuffer.write(makeFrame(timestampMs: 2))
        _ = preBuffer.write(makeFrame(timestampMs: 3))

        producer.start()

        // Allow some time for the polling loop to drain
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        await producer.stopAndDrain()

        var frames: [AudioFrame] = []
        for await frame in stream {
            frames.append(frame)
        }

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].timestampMs, 1)
        XCTAssertEqual(frames[1].timestampMs, 2)
        XCTAssertEqual(frames[2].timestampMs, 3)
    }

    func testStopAndDrainFlushesRemaining() async {
        let preBuffer = PreBuffer(capacity: 100)
        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let logger = MockLogger()

        let producer = FrameProducer(preBuffer: preBuffer, continuation: continuation, logger: logger)

        producer.start()

        // Write after starting — the polling loop should pick them up
        _ = preBuffer.write(makeFrame(timestampMs: 10))

        // Give polling time to pick up the frame
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

        // Write one more right before stopping — stopAndDrain should flush it
        _ = preBuffer.write(makeFrame(timestampMs: 20))

        await producer.stopAndDrain()

        var frames: [AudioFrame] = []
        for await frame in stream {
            frames.append(frame)
        }

        XCTAssertEqual(frames.count, 2)
    }

    func testEmptyPreBufferProducesNoFrames() async {
        let preBuffer = PreBuffer(capacity: 100)
        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let logger = MockLogger()

        let producer = FrameProducer(preBuffer: preBuffer, continuation: continuation, logger: logger)

        producer.start()
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        await producer.stopAndDrain()

        var frames: [AudioFrame] = []
        for await frame in stream {
            frames.append(frame)
        }

        XCTAssertTrue(frames.isEmpty)
    }
}
