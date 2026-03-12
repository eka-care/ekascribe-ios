import Foundation
import os

final class PreBuffer: @unchecked Sendable {
    private let capacity: Int
    private var buffer: [AudioFrame?]
    private var writeIndex = 0
    private var readIndex = 0
    private var count = 0
    private let lock = NSLock()

    init(capacity: Int = 2000) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    func write(_ frame: AudioFrame) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard count < capacity else { return false }

        buffer[writeIndex] = frame
        writeIndex = (writeIndex + 1) % capacity
        count += 1
        return true
    }

    func drain() -> [AudioFrame] {
        lock.lock()
        defer { lock.unlock() }

        guard count > 0 else { return [] }
        var frames: [AudioFrame] = []
        frames.reserveCapacity(count)

        for _ in 0..<count {
            if let frame = buffer[readIndex] {
                frames.append(frame)
                buffer[readIndex] = nil
            }
            readIndex = (readIndex + 1) % capacity
        }
        count = 0
        return frames
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        readIndex = 0
        count = 0
        buffer = Array(repeating: nil, count: capacity)
    }
}
