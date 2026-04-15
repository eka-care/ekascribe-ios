import Foundation

actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.permits = max(0, value)
    }

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let continuation = waiters.first {
            waiters.removeFirst()
            continuation.resume()
        } else {
            permits += 1
        }
    }
}
