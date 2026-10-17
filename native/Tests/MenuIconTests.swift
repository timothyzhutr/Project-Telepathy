import AppKit

// Exercise the bundle-name lookup used by macOS's input-source menu. Loading
// the PDF directly misses collisions with another image of the same basename.
let bundle = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let info = bundle.infoDictionary!
let modes = (info["ComponentInputModeDict"] as! [String: Any])["tsInputModeListKey"] as! [String: [String: Any]]
// The system can display the parent input method, not only its Hans mode.
// Without an explicit parent icon it falls back to the opaque app tile.
var resources = [info["tsInputMethodIconFileKey"] as? String ?? info["CFBundleIconFile"] as! String]
for mode in modes.values {
  for key in ["tsInputModeMenuIconFileKey", "tsInputModeAlternateMenuIconFileKey", "tsInputModePaletteIconFileKey"] {
    resources.append(mode[key] as! String)
  }
}
for resource in resources {
  let name = (resource as NSString).deletingPathExtension
  guard let image = bundle.image(forResource: name) else {
    fputs("FAIL: Missing input-source icon: \(resource)\n", stderr)
    exit(1)
  }
  for size in [18, 36] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 18, height: 18)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    NSGraphicsContext.restoreGraphicsState()
    let transparent = (0..<size).reduce(0) { count, y in
      count + (0..<size).filter { bitmap.colorAt(x: $0, y: y)!.alphaComponent < 0.01 }.count
    }
    // The thin link mark leaves most pixels clear. The rounded app tile
    // becomes a solid block when the menu tints its alpha as a template.
    let clearFraction = Double(transparent) / Double(size * size)
    guard clearFraction > 0.5 && clearFraction < 0.95 else {
      fputs("FAIL: \(resource) does not render a visible transparent mark at \(size) px (\(transparent)/\(size * size) clear pixels).\n", stderr)
      exit(1)
    }
  }
}
print("Parent and mode icons resolve to the transparent link mark at 1× and 2×.")
