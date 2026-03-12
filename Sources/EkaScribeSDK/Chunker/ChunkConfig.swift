import Foundation

struct ChunkConfig {
    let preferredDurationSec: Int
    let desperationDurationSec: Int
    let maxDurationSec: Int
    let longSilenceSec: Double
    let shortSilenceSec: Double
    let overlapDurationSec: Double

    init(
        preferredDurationSec: Int = 10,
        desperationDurationSec: Int = 20,
        maxDurationSec: Int = 25,
        longSilenceSec: Double = 0.5,
        shortSilenceSec: Double = 0.1,
        overlapDurationSec: Double = 0.5
    ) {
        self.preferredDurationSec = preferredDurationSec
        self.desperationDurationSec = desperationDurationSec
        self.maxDurationSec = maxDurationSec
        self.longSilenceSec = longSilenceSec
        self.shortSilenceSec = shortSilenceSec
        self.overlapDurationSec = overlapDurationSec
    }
}
