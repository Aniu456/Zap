import Foundation

enum CaptureTool: Equatable {
    case box
    case arrow
    case pencil
    case marker
    case mosaic
    case text
    case eraser
}

/// Marks are stored in crop-image pixels. Origin is the top-left, y grows downward.
enum CaptureMark: Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case box(CGRect)
    case text(String, origin: CGPoint, fontSize: CGFloat)
    case mosaic(CGRect)
    case stroke(points: [CGPoint], width: CGFloat, alpha: CGFloat)
}
