import CoreGraphics

/// Pure layout for margin marks. Input marks sit at a vertical span in view space (top-down);
/// output markers never overlap: nearby marks merge into one stacked marker.
public enum MarginLayout {
    public struct Mark: Equatable {
        public var id: Int
        public var minY: CGFloat
        public var maxY: CGFloat
        public var color: Int
        public var isNote: Bool
        public init(id: Int, minY: CGFloat, maxY: CGFloat, color: Int, isNote: Bool = false) {
            self.id = id; self.minY = minY; self.maxY = maxY; self.color = color; self.isNote = isNote
        }
    }

    public struct Marker: Equatable {
        public var ids: [Int]
        public var minY: CGFloat
        public var maxY: CGFloat
        public var colors: [Int]
        public var hasNote: Bool
        public var count: Int { ids.count }
        public var midY: CGFloat { (minY + maxY) / 2 }
    }

    /// Marks whose spans are within `gap` of each other merge. Non-finite marks are dropped.
    public static func markers(for marks: [Mark], gap: CGFloat = 6) -> [Marker] {
        let valid = marks.filter { $0.minY.isFinite && $0.maxY.isFinite }
            .map { Mark(id: $0.id, minY: min($0.minY, $0.maxY), maxY: max($0.minY, $0.maxY), color: $0.color, isNote: $0.isNote) }
            .sorted { ($0.minY, $0.id) < ($1.minY, $1.id) }
        var result: [Marker] = []
        for mark in valid {
            if var last = result.last, mark.minY <= last.maxY + gap {
                last.ids.append(mark.id)
                last.maxY = max(last.maxY, mark.maxY)
                if !last.colors.contains(mark.color) { last.colors.append(mark.color) }
                last.hasNote = last.hasNote || mark.isNote
                result[result.count - 1] = last
            } else {
                result.append(Marker(ids: [mark.id], minY: mark.minY, maxY: mark.maxY, colors: [mark.color], hasNote: mark.isNote))
            }
        }
        return result
    }

    /// Which page edge carries the markers, in view (top-down) terms: the edge a text line starts at.
    /// Lines run horizontally at 0/180 degrees (marks stack along Y on the left/right edge) and vertically at
    /// 90/270 (marks stack along X on the top/bottom edge), so a mark always sits beside its own line.
    public enum Side: Equatable { case left, right, top, bottom
        /// True when markers are spread along X (top/bottom edge).
        public var spansX: Bool { self == .top || self == .bottom }
    }

    public static func side(forRotation rotation: Int) -> Side {
        switch ((rotation % 360) + 360) % 360 {
        case 90: return .top
        case 180: return .right
        case 270: return .bottom
        default: return .left
        }
    }

    /// Marker rectangle in view space. `outside` puts it in the gutter beside the page edge, else just inside it.
    public static func rect(for marker: Marker, side: Side, pageRect: CGRect, outside: Bool,
                            flipped: Bool = true, thickness: CGFloat = 6) -> CGRect {
        let length = max(8, marker.maxY - marker.minY)
        let mid = marker.midY
        switch side {
        case .left:
            return CGRect(x: outside ? pageRect.minX - 11 : pageRect.minX + 2, y: mid - length / 2, width: thickness, height: length)
        case .right:
            return CGRect(x: outside ? pageRect.maxX + 5 : pageRect.maxX - 8, y: mid - length / 2, width: thickness, height: length)
        case .top, .bottom:
            let atMinY = (side == .top) == flipped
            let y: CGFloat = atMinY ? (outside ? pageRect.minY - 11 : pageRect.minY + 2)
                                    : (outside ? pageRect.maxY + 5 : pageRect.maxY - 8)
            return CGRect(x: mid - length / 2, y: y, width: length, height: thickness)
        }
    }
}
