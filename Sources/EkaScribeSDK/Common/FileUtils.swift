import Foundation

func deleteFile(_ file: URL, logger: Logger? = nil) {
    do {
        try FileManager.default.removeItem(at: file)
    } catch {
        logger?.error("FileUtils", "Failed to delete file: \(file.path)", error)
    }
}

extension URL {
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }
}
