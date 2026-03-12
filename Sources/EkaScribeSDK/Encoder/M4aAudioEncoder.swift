import AVFoundation
import CoreMedia
import Foundation

final class M4aAudioEncoder: AudioEncoder {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func encode(frames: [AudioFrame], sampleRate: Int, outputPath: String) async throws -> EncodedChunk {
        let pcm = frames.flatMap { $0.pcm }
        let durationMs = Int64(pcm.count) * 1000 / Int64(max(1, sampleRate))
        let outputURL = URL(fileURLWithPath: outputPath)

        do {
            try await encodeAsM4A(pcm: pcm, sampleRate: sampleRate, outputURL: outputURL)
            let size = try fileSize(atPath: outputPath)
            return EncodedChunk(filePath: outputPath, format: .m4a, sizeBytes: size, durationMs: durationMs)
        } catch {
            logger.error("Encoder", "M4A encoding failed, falling back to WAV", error)
            let wavPath = outputPath.replacingOccurrences(of: ".m4a", with: ".wav")
            return try encodeAsWav(pcm: pcm, sampleRate: sampleRate, outputPath: wavPath, durationMs: durationMs)
        }
    }

    // MARK: - M4A Encoding (CAF → AVAssetExportSession)

    /// Encodes raw PCM Int16 data to M4A using a two-step process:
    /// 1. Write PCM to a temporary CAF file via AVAudioFile (proper format description)
    /// 2. Convert CAF → M4A via AVAssetExportSession (software AAC, works on simulator + device)
    private func encodeAsM4A(pcm: [Int16], sampleRate: Int, outputURL: URL) async throws {
        // Step 1: Write PCM samples to a temporary CAF file
        let cafURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
        try writePCMToCAF(pcm: pcm, sampleRate: sampleRate, cafURL: cafURL)

        defer {
            // Always clean up the intermediate CAF file
            try? FileManager.default.removeItem(at: cafURL)
        }

        // Step 2: Convert CAF → M4A using AVAssetExportSession
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await convertCAFToM4A(cafURL: cafURL, m4aURL: outputURL)
    }

    /// Writes raw PCM Int16 samples to a CAF file using AVAudioFile.
    /// AVAudioFile correctly creates the audio format description needed for AAC conversion.
    private func writePCMToCAF(pcm: [Int16], sampleRate: Int, cafURL: URL) throws {
        if FileManager.default.fileExists(atPath: cafURL.path) {
            try FileManager.default.removeItem(at: cafURL)
        }

        // Create the PCM format that matches our Int16 data
        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to create PCM audio format")
        }

        // Create the AVAudioFile for writing
        let audioFile = try AVAudioFile(
            forWriting: cafURL,
            settings: pcmFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // Create a buffer and fill it with our PCM data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(pcm.count)) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to create AVAudioPCMBuffer")
        }
        buffer.frameLength = AVAudioFrameCount(pcm.count)

        guard let channelData = buffer.int16ChannelData?[0] else {
            throw ScribeException(code: .encoderFailed, message: "Failed to get int16 channel data from buffer")
        }

        pcm.withUnsafeBufferPointer { srcPtr in
            channelData.update(from: srcPtr.baseAddress!, count: pcm.count)
        }

        try audioFile.write(from: buffer)
        logger.info("Encoder", "CAF file written: \(cafURL.lastPathComponent), samples=\(pcm.count)")
    }

    /// Converts a CAF file to M4A using AVAssetExportSession.
    /// Uses withCheckedThrowingContinuation to avoid blocking (no priority inversion).
    private func convertCAFToM4A(cafURL: URL, m4aURL: URL) async throws {
        let asset = AVURLAsset(url: cafURL)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ScribeException(
                code: .encoderFailed,
                message: "Failed to create AVAssetExportSession"
            )
        }

        exporter.outputFileType = .m4a
        exporter.outputURL = m4aURL

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let error = exporter.error ?? ScribeException(
                        code: .encoderFailed,
                        message: "AVAssetExportSession failed with status: \(exporter.status.rawValue)"
                    )
                    continuation.resume(throwing: error)
                default:
                    continuation.resume(throwing: ScribeException(
                        code: .encoderFailed,
                        message: "AVAssetExportSession unexpected status: \(exporter.status.rawValue)"
                    ))
                }
            }
        }

        logger.info("Encoder", "M4A file written: \(m4aURL.lastPathComponent)")
    }

    // MARK: - Encode From File (Full Audio)

    func encodeFromFile(pcmFilePath: String, sampleRate: Int, outputPath: String) async throws -> EncodedChunk {
        let pcmFileURL = URL(fileURLWithPath: pcmFilePath)
        guard FileManager.default.fileExists(atPath: pcmFilePath) else {
            throw ScribeException(code: .encoderFailed, message: "Raw PCM file not found: \(pcmFilePath)")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: pcmFilePath)
        let pcmFileSize = (attrs[.size] as? Int64) ?? 0
        guard pcmFileSize > 0 else {
            throw ScribeException(code: .encoderFailed, message: "Raw PCM file is empty")
        }

        let sampleCount = pcmFileSize / 2 // 16-bit = 2 bytes per sample
        let durationMs = sampleCount * 1000 / Int64(max(1, sampleRate))
        let outputURL = URL(fileURLWithPath: outputPath)

        do {
            // Write raw PCM file to temporary CAF, then convert to M4A
            let cafURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
            try writePCMFileToCAF(pcmFileURL: pcmFileURL, sampleRate: sampleRate, cafURL: cafURL)

            defer {
                try? FileManager.default.removeItem(at: cafURL)
            }

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            try await convertCAFToM4A(cafURL: cafURL, m4aURL: outputURL)
            let size = try fileSize(atPath: outputPath)
            return EncodedChunk(filePath: outputPath, format: .m4a, sizeBytes: size, durationMs: durationMs)
        } catch {
            logger.error("Encoder", "M4A encoding failed for full audio, falling back to WAV", error)
            let wavPath = outputPath.replacingOccurrences(of: ".m4a", with: ".wav")
            // Stream WAV from raw PCM file — no memory spike
            return try encodeWavFromFile(pcmFilePath: pcmFilePath, sampleRate: sampleRate, outputPath: wavPath, durationMs: durationMs)
        }
    }

    /// Writes a raw PCM file to a CAF file using AVAudioFile.
    /// Streams in chunks to avoid loading the entire file into memory for large recordings.
    private func writePCMFileToCAF(pcmFileURL: URL, sampleRate: Int, cafURL: URL) throws {
        if FileManager.default.fileExists(atPath: cafURL.path) {
            try FileManager.default.removeItem(at: cafURL)
        }

        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to create PCM audio format for file conversion")
        }

        let audioFile = try AVAudioFile(
            forWriting: cafURL,
            settings: pcmFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        guard let inputHandle = FileHandle(forReadingAtPath: pcmFileURL.path) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to open raw PCM file for reading")
        }
        defer { inputHandle.closeFile() }

        // Stream in 64KB chunks (32768 samples at 16-bit) to keep memory low
        let bytesPerChunk = 65536
        let samplesPerChunk = bytesPerChunk / MemoryLayout<Int16>.size

        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(samplesPerChunk)) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to create AVAudioPCMBuffer for streaming")
        }

        while autoreleasepool(invoking: {
            let data = inputHandle.readData(ofLength: bytesPerChunk)
            if data.isEmpty { return false }

            let sampleCount = data.count / MemoryLayout<Int16>.size
            buffer.frameLength = AVAudioFrameCount(sampleCount)

            guard let channelData = buffer.int16ChannelData?[0] else { return false }
            data.withUnsafeBytes { rawBuffer in
                guard let srcPtr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
                channelData.update(from: srcPtr, count: sampleCount)
            }

            do {
                try audioFile.write(from: buffer)
                return true
            } catch {
                logger.error("Encoder", "Failed to write chunk to CAF file", error)
                return false
            }
        }) {}

        logger.info("Encoder", "CAF file written from PCM stream: \(cafURL.lastPathComponent)")
    }

    // MARK: - WAV Fallback

    private func encodeWavFromFile(pcmFilePath: String, sampleRate: Int, outputPath: String, durationMs: Int64) throws -> EncodedChunk {
        let outputURL = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: pcmFilePath)
        let dataSize = UInt32((attrs[.size] as? Int64) ?? 0)

        // Write WAV header
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let riffSize: UInt32 = 36 + dataSize

        var header = Data(capacity: 44)
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian, Array.init))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        FileManager.default.createFile(atPath: outputPath, contents: nil)
        guard let outputHandle = FileHandle(forWritingAtPath: outputPath) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to open WAV output file")
        }
        defer { outputHandle.closeFile() }

        outputHandle.write(header)

        // Stream PCM data in 64KB chunks — avoids loading full file into memory
        guard let inputHandle = FileHandle(forReadingAtPath: pcmFilePath) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to open raw PCM file")
        }
        defer { inputHandle.closeFile() }

        let chunkSize = 65536
        while autoreleasepool(invoking: {
            let chunk = inputHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { return false }
            outputHandle.write(chunk)
            return true
        }) {}

        let size = (try? fileSize(atPath: outputPath)) ?? 0
        return EncodedChunk(filePath: outputPath, format: .wav, sizeBytes: size, durationMs: durationMs)
    }

    private func encodeAsWav(pcm: [Int16], sampleRate: Int, outputPath: String, durationMs: Int64) throws -> EncodedChunk {
        let outputURL = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(pcm.count * MemoryLayout<Int16>.size)
        let riffSize: UInt32 = 36 + dataSize

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian, Array.init))
        wav.append("WAVE".data(using: .ascii)!)

        wav.append("fmt ".data(using: .ascii)!)
        let fmtSize: UInt32 = 16
        let audioFormat: UInt16 = 1
        let sampleRateLE = UInt32(sampleRate).littleEndian
        let byteRateLE = byteRate.littleEndian
        let blockAlignLE = blockAlign.littleEndian
        let bitsPerSampleLE = bitsPerSample.littleEndian

        wav.append(contentsOf: withUnsafeBytes(of: fmtSize.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: sampleRateLE, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: byteRateLE, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: blockAlignLE, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: bitsPerSampleLE, Array.init))

        wav.append("data".data(using: .ascii)!)
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        for sample in pcm {
            wav.append(contentsOf: withUnsafeBytes(of: sample.littleEndian, Array.init))
        }

        do {
            try wav.write(to: outputURL, options: .atomic)
            let size = (try? fileSize(atPath: outputPath)) ?? 0
            return EncodedChunk(filePath: outputPath, format: .wav, sizeBytes: size, durationMs: durationMs)
        } catch {
            logger.error("Encoder", "WAV fallback write failed", error)
            throw ScribeException(code: .encoderFailed, message: "Both M4A and WAV encoding failed", cause: error)
        }
    }

    private func fileSize(atPath path: String) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.size] as? Int64) ?? 0
    }
}
