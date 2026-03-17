import Foundation
import Atomics

final class PreBuffer: @unchecked Sendable {
    private let capacity: Int
    private var buffer: [AudioFrame?]
    private let writeIndex = ManagedAtomic<Int>(0)
    private let readIndex = ManagedAtomic<Int>(0)
    private let count = ManagedAtomic<Int>(0)

    init(capacity: Int = 2000) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    func write(_ frame: AudioFrame) -> Bool {
        guard count.load(ordering: .acquiring) < capacity else { return false }

        let index = writeIndex.load(ordering: .relaxed)
        buffer[index] = frame
        writeIndex.store((index + 1) % capacity, ordering: .releasing)
        count.wrappingIncrement(ordering: .releasing)
        return true
    }

    func drain() -> [AudioFrame] {
        let currentCount = count.load(ordering: .acquiring)
        guard currentCount > 0 else { return [] }

        var frames: [AudioFrame] = []
        frames.reserveCapacity(currentCount)

        var index = readIndex.load(ordering: .relaxed)
        for _ in 0..<currentCount {
            if let frame = buffer[index] {
                frames.append(frame)
                buffer[index] = nil
            }
            index = (index + 1) % capacity
        }

        readIndex.store(index, ordering: .releasing)
        count.wrappingDecrement(by: currentCount, ordering: .releasing)
        return frames
    }

    func clear() {
        writeIndex.store(0, ordering: .relaxed)
        readIndex.store(0, ordering: .relaxed)
        count.store(0, ordering: .relaxed)
        buffer = Array(repeating: nil, count: capacity)
    }
}
