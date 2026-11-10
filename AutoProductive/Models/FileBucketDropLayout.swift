import Foundation

enum FileBucketDropLayout {
    static func cardFrame(pointer: CGPoint, screen: CGRect) -> CGRect? {
        guard screen.width > 0, screen.height > 0, screen.contains(pointer) else { return nil }
        let distances = [pointer.x - screen.minX, screen.maxX - pointer.x,
                         pointer.y - screen.minY, screen.maxY - pointer.y]
        guard let edge = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[edge] < 18 else { return nil }
        let width = min(CGFloat(236), screen.width), height = min(CGFloat(88), screen.height)
        var x = min(max(pointer.x - width / 2, screen.minX), screen.maxX - width)
        var y = min(max(pointer.y - height / 2, screen.minY), screen.maxY - height)
        switch edge {
        case 0: x = screen.minX
        case 1: x = screen.maxX - width
        case 2: y = screen.minY
        default: y = screen.maxY - height
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
