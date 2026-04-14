import XCTest
@testable import PingMonitor

final class QualityEngineTests: XCTestCase {

    func testQualityDimensionScoresAverage() {
        let scores = QualityDimensionScores(
            latency: 90,
            stability: 80,
            path: 70,
            bandwidth: 60,
            resolution: 50,
            overlay: 40
        )
        // (90 + 80 + 70 + 60 + 50 + 40) / 6.0 = 390 / 6 = 65
        XCTAssertEqual(scores.average, 65, "The average dimension score should be calculated correctly.")
    }

    func testGlobalQualitySnapshotEmpty() {
        let dimensions = QualityDimensionScores(latency: 0, stability: 0, path: 0, bandwidth: 0, resolution: 0, overlay: 0)
        let snapshot = GlobalQualitySnapshot(
            window: .oneMinute,
            score: 0,
            dimensions: dimensions,
            hostCount: 0,
            healthyHostCount: 0,
            degradedHostCount: 0,
            criticalHostCount: 0,
            averageP95Latency: nil,
            averagePacketLoss: 0.0,
            averageJitter: 0.0,
            tunnelShare: 0.0,
            worstHosts: [],
            recentEvents: []
        )
        
        XCTAssertEqual(snapshot.score, 0)
        XCTAssertEqual(snapshot.hostCount, 0)
        XCTAssertNil(snapshot.averageP95Latency)
    }
}
