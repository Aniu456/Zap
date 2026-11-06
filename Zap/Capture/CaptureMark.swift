import Foundation

enum CaptureTool: Equatable {
    case arrow
    case box
    case text
    case mosaic
}

/// Marks are stored in crop-image pixels. Origin is the top-left, y grows downward.
enum CaptureMark: Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case box(CGRect)
    case text(String, origin: CGPoint, fontSize: CGFloat)
    case mosaic(CGRect)
}
