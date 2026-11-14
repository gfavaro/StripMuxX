import AppKit

/// AX clients commonly quantize geometry to whole points. Quantize the edges
/// once, before comparing targets, so fractional tiles never differ by rounding.
func windowMotionNativeTarget(_ frame: CGRect) -> CGRect {
    let x = frame.minX.rounded()
    let y = frame.minY.rounded()
    return CGRect(x: x, y: y, width: frame.maxX.rounded() - x, height: frame.maxY.rounded() - y)
}
