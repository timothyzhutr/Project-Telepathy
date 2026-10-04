// Original Telepathy artwork renderer. GPL-3.0-only.
// Geometry is read from the editable SVG sources by build_branding.py.
import AppKit
import CoreGraphics

let specURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let work = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: specURL)) as! [String: Any]
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
  let value = UInt32(hex.dropFirst(), radix: 16)!
  return CGColor(colorSpace: colorSpace, components: [CGFloat((value >> 16) & 255) / 255,
       CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, alpha])!
}

func mark(_ context: CGContext, color: CGColor) {
  context.setStrokeColor(color)
  context.setFillColor(color)
  context.setLineWidth(spec["stroke"] as! CGFloat)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  for commands in spec["paths"] as! [[[Any]]] {
    let path = CGMutablePath()
    var point = CGPoint.zero
    for command in commands {
      let name = command[0] as! String
      let values = command.dropFirst().map { CGFloat(($0 as! NSNumber).doubleValue) }
      switch name {
      case "M": point = CGPoint(x: values[0], y: values[1]); path.move(to: point)
      case "L": point = CGPoint(x: values[0], y: values[1]); path.addLine(to: point)
      case "H": point.x = values[0]; path.addLine(to: point)
      case "V": point.y = values[0]; path.addLine(to: point)
      case "C":
        point = CGPoint(x: values[4], y: values[5])
        path.addCurve(to: point, control1: CGPoint(x: values[0], y: values[1]),
                      control2: CGPoint(x: values[2], y: values[3]))
      default: fatalError("Unsupported SVG command")
      }
    }
    context.addPath(path)
    context.strokePath()
  }
  for circle in spec["circles"] as! [[CGFloat]] {
    context.fillEllipse(in: CGRect(x: circle[0] - circle[2], y: circle[1] - circle[2],
                                  width: circle[2] * 2, height: circle[2] * 2))
  }
}

func tile(_ context: CGContext) {
  let values = spec["tile"] as! [CGFloat]
  let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
  let path = CGPath(roundedRect: rect, cornerWidth: values[4], cornerHeight: values[4], transform: nil)
  context.saveGState()
  // CoreGraphics shadows use device units rather than scaling with the CTM.
  let shadowScale = abs(context.ctm.a)
  context.setShadow(offset: CGSize(width: 0, height: -10 * shadowScale), blur: 20 * shadowScale,
                    color: color("#0C3026", alpha: 0.2))
  context.addPath(path)
  context.setFillColor(color("#174C3D"))
  context.fillPath()
  context.restoreGState()
  context.saveGState()
  context.addPath(path)
  context.clip()
  let colors = (spec["gradient"] as! [String]).map { color($0) }
  let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
  context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                             end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
  context.restoreGState()
  context.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: values[4] - 1,
                        cornerHeight: values[4] - 1, transform: nil))
  context.setStrokeColor(color("#FFFFFF", alpha: 0.16))
  context.setLineWidth(2)
  context.strokePath()
  context.saveGState()
  let transform = spec["markTransform"] as! [CGFloat]
  context.translateBy(x: transform[0], y: transform[1])
  context.scaleBy(x: transform[2], y: transform[2])
  mark(context, color: color(spec["markColor"] as! String))
  context.restoreGState()
}

func png(_ size: Int, app: Bool, name: String, destination: URL = output) throws {
  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: size * 4, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.translateBy(x: 0, y: CGFloat(size))
  context.scaleBy(x: CGFloat(size) / (app ? 1024 : 24), y: -CGFloat(size) / (app ? 1024 : 24))
  if app { tile(context) } else { mark(context, color: color("#000000")) }
  let image = NSBitmapImageRep(cgImage: context.makeImage()!)
  try image.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}

let iconset = work.appendingPathComponent("Telepathy.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  try png(size, app: true, name: "icon_\(size)x\(size).png", destination: iconset)
  try png(size * 2, app: true, name: "icon_\(size)x\(size)@2x.png", destination: iconset)
}
try png(128, app: true, name: "Telepathy-128.png")
for size in [16, 18, 22] {
  try png(size, app: false, name: "menu-\(size).png", destination: work)
  try png(size * 2, app: false, name: "menu-\(size)@2x.png", destination: work)
}
var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdf = CGContext(output.appendingPathComponent("Telepathy.pdf") as CFURL, mediaBox: &mediaBox,
                    [kCGPDFContextTitle: "Telepathy Context link", kCGPDFContextCreator: "Project Telepathy"] as CFDictionary)!
pdf.beginPDFPage(nil)
pdf.translateBy(x: 0, y: 18)
pdf.scaleBy(x: 18 / 24, y: -18 / 24)
mark(pdf, color: color("#000000"))
pdf.endPDFPage()
pdf.closePDF()

// Documentation-only preview. The app ships just the .icns and template PDF.
let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 420,
     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
preview.size = NSSize(width: 660, height: 210)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
NSColor(srgbRed: 0.96, green: 0.97, blue: 0.95, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 660, height: 210).fill()
let appImage = NSImage(contentsOf: iconset.appendingPathComponent("icon_128x128@2x.png"))!
appImage.draw(in: NSRect(x: 22, y: 41, width: 128, height: 128))
let textAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13),
  .foregroundColor: NSColor(srgbRed: 0.35, green: 0.44, blue: 0.39, alpha: 1)]
"Context link · 16 / 18 / 22 pt".draw(at: NSPoint(x: 184, y: 163), withAttributes: textAttrs)
let previewContext = NSGraphicsContext.current!.cgContext
for (index, size) in [16, 18, 22].enumerated() {
  let x = CGFloat(192 + index * 75)
  previewContext.saveGState()
  previewContext.translateBy(x: x, y: 136)
  previewContext.scaleBy(x: CGFloat(size) / 24, y: -CGFloat(size) / 24)
  mark(previewContext, color: color("#000000"))
  previewContext.restoreGState()
  "\(size)".draw(at: NSPoint(x: x, y: 88), withAttributes: textAttrs)
}
let dark = NSRect(x: 464, y: 54, width: 168, height: 96)
NSColor(srgbRed: 0.1, green: 0.17, blue: 0.14, alpha: 1).setFill()
NSBezierPath(roundedRect: dark, xRadius: 12, yRadius: 12).fill()
for (index, size) in [16, 18, 22].enumerated() {
  previewContext.saveGState()
  previewContext.translateBy(x: CGFloat(485 + index * 48), y: 113)
  previewContext.scaleBy(x: CGFloat(size) / 24, y: -CGFloat(size) / 24)
  mark(previewContext, color: color("#FFFFFF"))
  previewContext.restoreGState()
}
"Template in light / dark menus".draw(at: NSPoint(x: 184, y: 38), withAttributes: textAttrs)
NSGraphicsContext.restoreGraphicsState()
try preview.representation(using: .png, properties: [:])!.write(to: work.appendingPathComponent("brand-preview.png"))
