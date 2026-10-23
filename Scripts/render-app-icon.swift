import AppKit

// Run from the project root: swift Scripts/render-app-icon.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let canvas = 1024
let markHeight: CGFloat = 740
let markWidth = markHeight * 360 / 480

func render(sourcePath: String, background: UInt32, filename: String) throws {
  let source = root.appendingPathComponent(sourcePath)
  let output = root.appendingPathComponent(
    "SeruendeshAI/Assets.xcassets/AppIcon.appiconset/\(filename)")
  guard let logo = NSImage(contentsOf: source),
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
      bytesPerRow: canvas * 4, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
  else {
    fatalError("Cannot load the source logo or create the icon canvas")
  }

  context.setFillColor(
    CGColor(
      srgbRed: CGFloat((background >> 16) & 255) / 255,
      green: CGFloat((background >> 8) & 255) / 255,
      blue: CGFloat(background & 255) / 255,
      alpha: 1
    ))
  context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  logo.draw(
    in: CGRect(
      x: (CGFloat(canvas) - markWidth) / 2,
      y: (CGFloat(canvas) - markHeight) / 2,
      width: markWidth, height: markHeight
    ))
  NSGraphicsContext.restoreGraphicsState()

  guard let image = context.makeImage(),
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  else {
    fatalError("Cannot encode the app icon")
  }
  try png.write(to: output, options: .atomic)
  print("Rendered opaque 1024×1024 \(filename) from the Secret Path SVG")
}

try render(
  sourcePath: "Design/Brand/secret-path.svg", background: 0xFAFAF5, filename: "AppIcon.png")
try render(
  sourcePath: "Design/Brand/secret-path-dark.svg",
  background: 0x101010, filename: "AppIcon-dark.png"
)
