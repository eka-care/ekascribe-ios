import Foundation

struct EncodedChunk {
    let filePath: String
    let format: AudioFormat
    let sizeBytes: Int
    let durationMs: Int

    enum AudioFormat {
        case wav
        case m4a

        var fileExtension: String {
            switch self {
            case .wav: return "wav"
            case .m4a: return "m4a"
            }
        }

        var mimeType: String {
            switch self {
            case .wav: return "audio/wav"
            case .m4a: return "audio/mp4"
            }
        }

        static func from(filePath: String) -> AudioFormat {
            let lower = filePath.lowercased()
            if lower.hasSuffix(".wav") || lower.hasSuffix(".wav_") {
                return .wav
            }
            return .m4a
        }
    }
}
