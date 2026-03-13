import XCTest
@testable import EkaScribeSDK

final class AudioQualityTests: XCTestCase {

    func testToMetricsConvertsAllFields() {
        let quality = AudioQuality(stoi: 0.85, pesq: 3.2, siSDR: 15.5, overallScore: 0.72)
        let metrics = quality.toMetrics()

        XCTAssertEqual(metrics.stoi, 0.85, accuracy: 0.001)
        XCTAssertEqual(metrics.pesq, 3.2, accuracy: 0.001)
        XCTAssertEqual(metrics.siSDR, 15.5, accuracy: 0.001)
        XCTAssertEqual(metrics.overallScore, 0.72, accuracy: 0.001)
    }

    func testToMetricsWithZeroValues() {
        let quality = AudioQuality(stoi: 0, pesq: 0, siSDR: 0, overallScore: 0)
        let metrics = quality.toMetrics()

        XCTAssertEqual(metrics.stoi, 0)
        XCTAssertEqual(metrics.pesq, 0)
        XCTAssertEqual(metrics.siSDR, 0)
        XCTAssertEqual(metrics.overallScore, 0)
    }

    func testToMetricsWithNegativeValues() {
        let quality = AudioQuality(stoi: 0.0, pesq: -0.5, siSDR: -20.0, overallScore: 0.0)
        let metrics = quality.toMetrics()

        XCTAssertEqual(metrics.pesq, -0.5, accuracy: 0.001)
        XCTAssertEqual(metrics.siSDR, -20.0, accuracy: 0.001)
    }
}
