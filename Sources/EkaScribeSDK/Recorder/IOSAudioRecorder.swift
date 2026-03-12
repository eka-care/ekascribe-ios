@preconcurrency import AVFoundation
import Foundation

final class IOSAudioRecorder: AudioRecorder {
    private let engine = AVAudioEngine()
    private let config: RecorderConfig
    private let logger: Logger
    private var frameIndex: Int64 = 0
    private var isPaused = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // Pre-allocated buffers reused in the real-time tap callback
    private var convertedBuffer: AVAudioPCMBuffer?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    var onFrame: ((AudioFrame) -> Void)?
    var onAudioFocusChanged: ((Bool) -> Void)?

    init(config: RecorderConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    func start() {
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setPreferredSampleRate(Double(config.sampleRate))
            try session.setActive(true)
            registerObservers()
            #endif

            let input = engine.inputNode
            let hwFormat = input.inputFormat(forBus: 0)

            // Target format: 16kHz mono Float32
            guard let tgtFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(config.sampleRate),
                channels: 1,
                interleaved: false
            ) else {
                logger.error("Recorder", "Failed to create target audio format")
                return
            }
            targetFormat = tgtFormat

            let needsConversion = hwFormat.sampleRate != tgtFormat.sampleRate
                || hwFormat.channelCount != tgtFormat.channelCount

            if needsConversion {
                converter = AVAudioConverter(from: hwFormat, to: tgtFormat)
                guard converter != nil else {
                    logger.error("Recorder", "Failed to create AVAudioConverter from \(hwFormat) to \(tgtFormat)")
                    return
                }
                // Pre-allocate output buffer with generous capacity (reused every callback)
                let maxOutputFrames: AVAudioFrameCount = 4096
                convertedBuffer = AVAudioPCMBuffer(pcmFormat: tgtFormat, frameCapacity: maxOutputFrames)
            }

            installAudioTap()
            engine.prepare()
            try engine.start()
            logger.info("Recorder", "Started recording: hw=\(hwFormat.sampleRate)Hz → target=\(config.sampleRate)Hz, needsConversion=\(needsConversion)")
        } catch {
            logger.error("Recorder", "Failed to start recorder", error)
        }
    }

    private func installAudioTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)

        let conv = converter
        let outBuf = convertedBuffer

        // Install tap with nil format (uses hardware format) to avoid format mismatch crash
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(config.frameSize), format: nil) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }

            let pcm: [Int16]

            if let conv, let outBuf {
                // Reset output buffer length for reuse
                outBuf.frameLength = 0

                nonisolated(unsafe) var allConsumed = false
                let inputBuffer = buffer
                var error: NSError?
                conv.convert(to: outBuf, error: &error) { _, outStatus in
                    if allConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                guard error == nil else { return }
                pcm = Self.floatBufferToInt16(outBuf)
            } else {
                pcm = Self.floatBufferToInt16(buffer)
            }

            guard !pcm.isEmpty else { return }

            let frame = AudioFrame(
                pcm: pcm,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                sampleRate: self.config.sampleRate,
                frameIndex: self.frameIndex
            )
            self.frameIndex += 1
            self.onFrame?(frame)
        }
    }

    private static func floatBufferToInt16(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let count = Int(buffer.frameLength)
        // Use unsafeUninitializedCapacity to avoid per-element append overhead
        return [Int16](unsafeUninitializedCapacity: count) { ptr, initializedCount in
            for i in 0..<count {
                let scaled = Int32(channelData[i] * 32767.0)
                ptr[i] = Int16(clamping: max(Int32(Int16.min), min(Int32(Int16.max), scaled)))
            }
            initializedCount = count
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        convertedBuffer = nil

        #if os(iOS)
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.warn("Recorder", "Failed to deactivate AVAudioSession", error)
        }
        #endif
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    #if os(iOS)
    private func registerObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else {
                return
            }

            switch type {
            case .began:
                self?.onAudioFocusChanged?(false)
            case .ended:
                let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                self?.onAudioFocusChanged?(options.contains(.shouldResume))
            @unknown default:
                break
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
            else { return }

            switch reason {
            case .oldDeviceUnavailable, .newDeviceAvailable:
                self.handleRouteChange()
            default:
                break
            }
        }
    }

    private func handleRouteChange() {
        // Notify client of temporary pause during mic switch
        onAudioFocusChanged?(false)

        guard engine.isRunning else {
            logger.warn("Recorder", "Audio engine stopped during route change, attempting restart")
            do {
                try engine.start()
            } catch {
                logger.error("Recorder", "Failed to restart audio engine after route change", error)
                return
            }
            return
        }

        let input = engine.inputNode
        // The hardware format can momentarily be 0 channels during switch; fallback if invalid
        let newHwFormat = input.inputFormat(forBus: 0)
        guard newHwFormat.sampleRate > 0 && newHwFormat.channelCount > 0 else {
            logger.warn("Recorder", "Invalid hardware format during route change: \(newHwFormat)")
            return
        }

        guard let tgtFormat = targetFormat else { return }

        let needsConversion = newHwFormat.sampleRate != tgtFormat.sampleRate
            || newHwFormat.channelCount != tgtFormat.channelCount

        // Recreate converter if hardware format changed
        if needsConversion {
            converter = AVAudioConverter(from: newHwFormat, to: tgtFormat)
            if converter == nil {
                logger.error("Recorder", "Failed to create AVAudioConverter after route change")
            }
            if convertedBuffer == nil {
                convertedBuffer = AVAudioPCMBuffer(pcmFormat: tgtFormat, frameCapacity: 4096)
            }
        } else {
            converter = nil
            convertedBuffer = nil
        }

        // Reinstall tap with updated converter
        // In rare route changes (e.g., Bluetooth disconnects), installing a tap or restarting the engine throws.
        // Swift does not always gracefully catch underlying CoreAudio C++ exceptions, 
        // but try-catching engine operations where possible minimizes crashes.
        do {
            input.removeTap(onBus: 0)
            installAudioTap()
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            logger.info("Recorder", "Audio route changed: new hw=\(newHwFormat.sampleRate)Hz, needsConversion=\(needsConversion)")
        } catch {
            logger.error("Recorder", "Failed to reinstall tap/restart engine after route change", error)
        }

        // Notify client recording can resume
        onAudioFocusChanged?(true)
    }
    #endif
}
