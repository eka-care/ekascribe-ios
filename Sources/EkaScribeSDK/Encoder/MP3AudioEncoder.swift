import AVFoundation
import Foundation
import SwiftLAME

final class MP3AudioEncoder: AudioEncoder {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - AudioEncoder

    func encode(frames: [AudioFrame], sampleRate: Int, outputPath: String) async throws -> EncodedChunk {
        let pcm = frames.flatMap { $0.pcm }
        let durationMs = pcm.count * 1000 / max(1, sampleRate)
        let outputURL = URL(fileURLWithPath: outputPath)

        do {
            try await encodeAsMP3(pcm: pcm, sampleRate: sampleRate, outputURL: outputURL)
            let size = try fileSize(atPath: outputPath)
            return EncodedChunk(filePath: outputPath, format: .mp3, sizeBytes: size, durationMs: durationMs)
        } catch {
            logger.error("Encoder", "MP3 encoding failed, falling back to WAV", error)
            let wavPath = outputPath.replacingOccurrences(of: ".mp3", with: ".wav")
            return try encodeAsWav(pcm: pcm, sampleRate: sampleRate, outputPath: wavPath, durationMs: durationMs)
        }
    }

    func encodeFromFile(pcmFilePath: String, sampleRate: Int, outputPath: String) async throws -> EncodedChunk {
        let pcmFileURL = URL(fileURLWithPath: pcmFilePath)
        guard FileManager.default.fileExists(atPath: pcmFilePath) else {
            throw ScribeException(code: .encoderFailed, message: "Raw PCM file not found: \(pcmFilePath)")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: pcmFilePath)
        let pcmFileSize = (attrs[.size] as? Int) ?? 0
        guard pcmFileSize > 0 else {
            throw ScribeException(code: .encoderFailed, message: "Raw PCM file is empty")
        }

        let sampleCount = pcmFileSize / 2
        let durationMs = sampleCount * 1000 / max(1, sampleRate)
        let outputURL = URL(fileURLWithPath: outputPath)

        do {
            let cafURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
            try writePCMFileToCAF(pcmFileURL: pcmFileURL, sampleRate: sampleRate, cafURL: cafURL)

            defer {
                try? FileManager.default.removeItem(at: cafURL)
            }

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            try await encodeCAFToMP3(cafURL: cafURL, outputURL: outputURL, sampleRate: sampleRate)
            let size = try fileSize(atPath: outputPath)
            return EncodedChunk(filePath: outputPath, format: .mp3, sizeBytes: size, durationMs: durationMs)
        } catch {
            logger.error("Encoder", "MP3 encoding failed for full audio, falling back to WAV", error)
            let wavPath = outputPath.replacingOccurrences(of: ".mp3", with: ".wav")
            return try encodeWavFromFile(pcmFilePath: pcmFilePath, sampleRate: sampleRate, outputPath: wavPath, durationMs: durationMs)
        }
    }

    // MARK: - MP3 Encoding

    private func encodeAsMP3(pcm: [Int16], sampleRate: Int, outputURL: URL) async throws {
        let cafURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
        try writePCMToCAF(pcm: pcm, sampleRate: sampleRate, cafURL: cafURL)

        defer {
            try? FileManager.default.removeItem(at: cafURL)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await encodeCAFToMP3(cafURL: cafURL, outputURL: outputURL, sampleRate: sampleRate)
    }

    private func encodeCAFToMP3(cafURL: URL, outputURL: URL, sampleRate: Int) async throws {
        let config = LameConfiguration(
            sampleRate: .custom(Int32(sampleRate)),
            bitrateMode: .constant(32),
            quality: .standard
        )
        let lameEncoder = try SwiftLameEncoder(sourceUrl: cafURL, configuration: config, destinationUrl: outputURL)
        try await lameEncoder.encode(priority: .userInitiated)
        logger.info("Encoder", "MP3 file written: \(outputURL.lastPathComponent)")
    }

    // MARK: - PCM to CAF

    private func writePCMToCAF(pcm: [Int16], sampleRate: Int, cafURL: URL) throws {
        if FileManager.default.fileExists(atPath: cafURL.path) {
            try FileManager.default.removeItem(at: cafURL)
        }

        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw ScribeException(code: .encoderFailed, message: "Failed to create PCM audio format")
        }

        let audioFile = try AVAudioFile(
            forWriting: cafURL,
            settings: pcmFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

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
    }

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
    }

    // MARK: - WAV Fallback

    private func encodeAsWav(pcm: [Int16], sampleRate: Int, outputPath: String, durationMs: Int) throws -> EncodedChunk {
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
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        wav.append("data".data(using: .ascii)!)
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        for sample in pcm {
            wav.append(contentsOf: withUnsafeBytes(of: sample.littleEndian, Array.init))
        }

        try wav.write(to: outputURL, options: .atomic)
        let size = (try? fileSize(atPath: outputPath)) ?? 0
        return EncodedChunk(filePath: outputPath, format: .wav, sizeBytes: size, durationMs: durationMs)
    }

    private func encodeWavFromFile(pcmFilePath: String, sampleRate: Int, outputPath: String, durationMs: Int) throws -> EncodedChunk {
        let outputURL = URL(fileURLWithPath: outputPath)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: pcmFilePath)
        let dataSize = UInt32((attrs[.size] as? Int) ?? 0)

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

    private func fileSize(atPath path: String) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.size] as? Int) ?? 0
    }
}
