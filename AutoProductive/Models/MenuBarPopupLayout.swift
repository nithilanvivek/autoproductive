import Foundation

struct MenuBarPopupLayout {
    static let pointerHeight: CGFloat = 10
    let frame: CGRect
    let tipX: CGFloat

    init(anchor: CGRect, visibleFrame: CGRect, preferredHeight: CGFloat = 550) {
        let margin = min(8.0, visibleFrame.width / 4)
        let width = max(1, min(340, visibleFrame.width - 2 * margin))
        let top = min(anchor.minY - 2, visibleFrame.maxY)
        let height = max(Self.pointerHeight + 1, min(preferredHeight + Self.pointerHeight, top - visibleFrame.minY - margin))
        let x = max(visibleFrame.minX + margin, min(anchor.midX - width / 2, visibleFrame.maxX - margin - width))
        frame = CGRect(x: x, y: top - height, width: width, height: height)
        let minimumTip = min(36.0, width / 2)
        tipX = max(minimumTip, min(anchor.midX - x, width - minimumTip))
    }
}
