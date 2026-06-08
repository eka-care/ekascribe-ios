import Foundation

struct EncodedChunk {
    let filePath: String
    let format: AudioFormat
    let sizeBytes: Int
    let durationMs: Int

    enum AudioFormat {
        case wav
        case m4a
        case mp3

        var fileExtension: String {
            switch self {
            case .wav: return "wav"
            case .m4a: return "m4a"
            case .mp3: return "mp3"
            }
        }

        var mimeType: String {
            switch self {
            case .wav: return "audio/wav"
            case .m4a: return "audio/mp4"
            case .mp3: return "audio/mpeg"
            }
        }

        static func from(filePath: String) -> AudioFormat {
            let lower = filePath.lowercased()
            if lower.hasSuffix(".wav") || lower.hasSuffix(".wav_") {
                return .wav
            }
            if lower.hasSuffix(".mp3") || lower.hasSuffix(".mp3_") {
                return .mp3
            }
            return .m4a
        }
    }
}
