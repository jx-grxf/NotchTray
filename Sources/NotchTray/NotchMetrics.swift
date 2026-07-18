import AppKit

/// Geometry of the built-in display's notch and menu bar.
///
/// All x values are global screen coordinates. AX reports item frames with a
/// top-left origin while NSScreen uses bottom-left, but x values are identical
/// in both systems, so visibility checks only compare x ranges.
struct NotchMetrics {
    let screen: NSScreen
    /// Horizontal band covered by the hardware notch.
    let notchXRange: ClosedRange<CGFloat>
    let menuBarHeight: CGFloat

    /// Right edge of the screen; status items must end before this.
    var maxVisibleX: CGFloat { screen.frame.maxX }
    /// Status items must start after the notch's right edge.
    var minVisibleX: CGFloat { notchXRange.upperBound }

    var notchWidth: CGFloat { notchXRange.upperBound - notchXRange.lowerBound }
    var notchCenterX: CGFloat { (notchXRange.lowerBound + notchXRange.upperBound) / 2 }

    static func detect() -> NotchMetrics? {
        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {
            guard let left = screen.auxiliaryTopLeftArea,
                  let right = screen.auxiliaryTopRightArea else { continue }
            return NotchMetrics(
                screen: screen,
                notchXRange: left.maxX...right.minX,
                menuBarHeight: screen.safeAreaInsets.top
            )
        }
        return nil
    }
}
