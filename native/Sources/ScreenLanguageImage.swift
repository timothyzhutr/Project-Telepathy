import AppKit

enum ScreenLanguageImage {
  static let maximumRequestBytes = 3 * 1024 * 1024
  static func scaledSize(_ size: CGSize, longestEdge: CGFloat = 960) -> CGSize {
    guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return .zero }
    let scale = min(1, longestEdge / max(size.width, size.height))
    return .init(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
  }
  static func markerRect(caret: CGRect, window: CGRect, primaryScreenHeight: CGFloat, output: CGSize) -> CGRect? {
    guard caret.height > 0, window.width > 0, window.height > 0 else { return nil }
    // IMK is AppKit global bottom-left; ScreenCaptureKit is global top-left,
    // relative to the primary display even on displays with negative origins.
    let topLeft = CGRect(x: caret.minX, y: primaryScreenHeight - caret.maxY,
                         width: max(1, caret.width), height: caret.height)
    guard window.intersects(topLeft) else { return nil }
    let sx = output.width / window.width, sy = output.height / window.height
    return CGRect(x: (topLeft.minX - window.minX) * sx, y: (topLeft.minY - window.minY) * sy,
                  width: topLeft.width * sx, height: topLeft.height * sy)
  }
  static func requestData(png: Data, revision: Int) -> Data? {
    guard let data = try? JSONSerialization.data(withJSONObject: ["revision": revision, "image": png.base64EncodedString()]),
          data.count <= maximumRequestBytes else { return nil }
    return data
  }
  static func png(_ image: CGImage, caret: CGRect, window: CGRect, primaryScreenHeight: CGFloat,
                  longestEdge: CGFloat = 960) -> Data? {
    let size = scaledSize(CGSize(width: image.width, height: image.height), longestEdge: longestEdge)
    guard size != .zero, let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: size))
    if let rect = markerRect(caret: caret, window: window, primaryScreenHeight: primaryScreenHeight, output: size) {
      var marker = rect.insetBy(dx: -8, dy: -5)
      marker.size.width = max(20, marker.width)
      marker.origin.y = size.height - marker.maxY
      context.setStrokeColor(CGColor(red: 0, green: 0.35, blue: 1, alpha: 1))
      context.setLineWidth(3)
      context.stroke(marker)
    }
    guard let result = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
  }
}
