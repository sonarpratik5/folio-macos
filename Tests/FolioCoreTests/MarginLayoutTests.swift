import XCTest
@testable import FolioCore

final class MarginLayoutTests: XCTestCase {
    func testMergesNearbyAndKeepsDistant() {
        let m = MarginLayout.markers(for: [
            .init(id: 1, minY: 10, maxY: 20, color: 0),
            .init(id: 2, minY: 24, maxY: 34, color: 1, isNote: true),
            .init(id: 3, minY: 100, maxY: 110, color: 2)
        ])
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].ids, [1, 2]); XCTAssertEqual(m[0].colors, [0, 1]); XCTAssertTrue(m[0].hasNote)
        XCTAssertEqual(m[0].maxY, 34); XCTAssertEqual(m[1].ids, [3]); XCTAssertFalse(m[1].hasNote)
    }
    func testUnsortedInvertedAndNonFinite() {
        let m = MarginLayout.markers(for: [
            .init(id: 2, minY: 200, maxY: 190, color: 0),
            .init(id: 1, minY: 0, maxY: 5, color: 0),
            .init(id: 9, minY: .nan, maxY: 5, color: 0)
        ])
        XCTAssertEqual(m.map(\.ids), [[1], [2]])
        XCTAssertEqual(m[1].minY, 190)
        XCTAssertTrue(MarginLayout.markers(for: []).isEmpty)
    }

    func testRotatedGeometryKeepsShortMarksBesideTheirLine() {
        XCTAssertEqual(MarginLayout.side(forRotation: 0), .left)
        XCTAssertEqual(MarginLayout.side(forRotation: 90), .top)
        XCTAssertEqual(MarginLayout.side(forRotation: 180), .right)
        XCTAssertEqual(MarginLayout.side(forRotation: 270), .bottom)
        XCTAssertEqual(MarginLayout.side(forRotation: -90), .bottom)
        let page = CGRect(x: 100, y: 50, width: 400, height: 600)
        // A vertical line in a 90-degree view: 12pt thick along X, 300pt long along Y. The span handed in is the X extent.
        let marker = MarginLayout.markers(for: [.init(id: 1, minY: 200, maxY: 212, color: 0)])[0]
        let top = MarginLayout.rect(for: marker, side: .top, pageRect: page, outside: true)
        XCTAssertEqual(top.width, 12); XCTAssertEqual(top.height, 6)
        XCTAssertEqual(top.midX, 206); XCTAssertLessThan(top.maxY, page.minY)
        let bottom = MarginLayout.rect(for: marker, side: .bottom, pageRect: page, outside: true)
        XCTAssertGreaterThan(bottom.minY, page.maxY); XCTAssertEqual(bottom.width, 12)
        let right = MarginLayout.rect(for: marker, side: .right, pageRect: page, outside: true)
        XCTAssertGreaterThan(right.minX, page.maxX); XCTAssertEqual(right.height, 12)
        let inside = MarginLayout.rect(for: marker, side: .top, pageRect: page, outside: false)
        XCTAssertGreaterThanOrEqual(inside.minY, page.minY)
    }
}
