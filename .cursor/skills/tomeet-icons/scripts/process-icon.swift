#!/usr/bin/swift
import AppKit
import Foundation

/// Punch a near-white plate to true alpha and optionally emit a warm-gray unselected state.
///
/// Usage:
///   swift process-icon.swift <input.png> [--no-unselected]
///
/// Writes `<stem>-cutout.png` and `<stem>-unselected.png` next to the input
/// (or into --out-dir if given).

let colorSpace = CGColorSpaceCreateDeviceRGB()

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
}

struct Args {
    var input: String
    var outDir: String?
    var makeUnselected = true
}

func parseArgs() -> Args {
    var args = CommandLine.arguments.dropFirst()
    var input: String?
    var outDir: String?
    var makeUnselected = true
    while let arg = args.first {
        args = args.dropFirst()
        if arg == "--no-unselected" {
            makeUnselected = false
        } else if arg == "--out-dir" {
            guard let dir = args.first else { fail("missing --out-dir path") }
            args = args.dropFirst()
            outDir = dir
        } else if arg.hasPrefix("-") {
            fail("unknown flag \(arg)")
        } else if input == nil {
            input = arg
        } else {
            fail("unexpected argument \(arg)")
        }
    }
    guard let input else { fail("usage: process-icon.swift <input.png> [--no-unselected] [--out-dir dir]") }
    return Args(input: input, outDir: outDir, makeUnselected: makeUnselected)
}

func loadCG(_ path: String) -> CGImage {
    guard let img = NSImage(contentsOf: URL(fileURLWithPath: path)),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("could not load \(path)")
    }
    return cg
}

func writePNG(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fail("write failed \(path)")
    }
}

func cutout(_ src: CGImage) -> CGImage {
    let w = src.width
    let h = src.height
    let bpr = w * 4
    var pixels = [UInt8](repeating: 0, count: h * bpr)
    let ctx = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bpr,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

    func lumaChroma(_ i: Int) -> (Float, Int) {
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        let y = 0.2126 * Float(r) + 0.7152 * Float(g) + 0.0722 * Float(b)
        let c = max(r, g, b) - min(r, g, b)
        return (y, c)
    }

    func isBgColor(_ i: Int) -> Bool {
        let (y, c) = lumaChroma(i)
        return y >= 228 && c <= 18
    }

    var isBg = [Bool](repeating: false, count: w * h)
    var queue: [Int] = []
    queue.reserveCapacity(w * 4)

    func consider(_ x: Int, _ y: Int) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let p = y * w + x
        if isBg[p] { return }
        if isBgColor(y * bpr + x * 4) {
            isBg[p] = true
            queue.append(p)
        }
    }

    for x in 0..<w { consider(x, 0); consider(x, h - 1) }
    for y in 0..<h { consider(0, y); consider(w - 1, y) }
    var qh = 0
    while qh < queue.count {
        let p = queue[qh]; qh += 1
        let x = p % w, y = p / w
        consider(x - 1, y); consider(x + 1, y); consider(x, y - 1); consider(x, y + 1)
    }

    var neighborBg = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let p = y * w + x
            if isBg[p] { continue }
            neighborBg[p] =
                (x > 0 && isBg[p - 1]) ||
                (x + 1 < w && isBg[p + 1]) ||
                (y > 0 && isBg[p - w]) ||
                (y + 1 < h && isBg[p + w])
        }
    }

    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let p = y * w + x
            let i = y * bpr + x * 4
            if isBg[p] {
                pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
                continue
            }
            if neighborBg[p] {
                let (yL, c) = lumaChroma(i)
                let t = min(1, max(0, (18 - Float(c)) / 18) * max(0, (yL - 210) / 30))
                let a = UInt8(max(0, min(255, Int((1 - t) * 255))))
                if a < 24 {
                    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
                    continue
                }
                let fa = Float(a) / 255
                pixels[i] = UInt8(Float(pixels[i]) * fa)
                pixels[i + 1] = UInt8(Float(pixels[i + 1]) * fa)
                pixels[i + 2] = UInt8(Float(pixels[i + 2]) * fa)
                pixels[i + 3] = a
            } else {
                pixels[i + 3] = 255
            }
            if pixels[i + 3] > 20 {
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }

    if maxX < minX { fail("no foreground found") }

    let pad = 40
    minX = max(0, minX - pad)
    minY = max(0, minY - pad)
    maxX = min(w - 1, maxX + pad)
    maxY = min(h - 1, maxY + pad)
    let outW = maxX - minX + 1
    let outH = maxY - minY + 1

    var outPixels = [UInt8](repeating: 0, count: outW * outH * 4)
    for y in 0..<outH {
        let srcOff = (minY + y) * bpr + minX * 4
        let dstOff = y * outW * 4
        outPixels.replaceSubrange(dstOff..<(dstOff + outW * 4), with: pixels[srcOff..<(srcOff + outW * 4)])
    }

    let outCtx = CGContext(
        data: &outPixels,
        width: outW,
        height: outH,
        bitsPerComponent: 8,
        bytesPerRow: outW * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    guard let image = outCtx.makeImage() else { fail("cutout image failed") }
    return image
}

func unselected(_ src: CGImage) -> CGImage {
    let w = src.width
    let h = src.height
    let bpr = w * 4
    var pixels = [UInt8](repeating: 0, count: h * bpr)
    let ctx = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bpr,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

    for i in stride(from: 0, to: pixels.count, by: 4) {
        let a = pixels[i + 3]
        if a < 20 {
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            continue
        }
        let fa = Float(a) / 255
        let r = Float(pixels[i]) / max(fa, 0.001)
        let g = Float(pixels[i + 1]) / max(fa, 0.001)
        let b = Float(pixels[i + 2]) / max(fa, 0.001)
        var y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        y = 198 + (y - 198) * 0.42
        y = max(148, min(228, y))
        let na = fa * 0.82
        pixels[i] = UInt8(max(0, min(255, y * 1.01 * na)))
        pixels[i + 1] = UInt8(max(0, min(255, y * 0.96 * na)))
        pixels[i + 2] = UInt8(max(0, min(255, y * 0.90 * na)))
        pixels[i + 3] = UInt8(max(0, min(255, na * 255)))
    }

    let outCtx = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bpr,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    guard let image = outCtx.makeImage() else { fail("unselected image failed") }
    return image
}

let args = parseArgs()
let inputURL = URL(fileURLWithPath: args.input)
let stem = inputURL.deletingPathExtension().lastPathComponent
let dir = args.outDir ?? inputURL.deletingLastPathComponent().path
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let cutoutPath = "\(dir)/\(stem)-cutout.png"
let unselectedPath = "\(dir)/\(stem)-unselected.png"

let cut = cutout(loadCG(args.input))
writePNG(cut, to: cutoutPath)
print("wrote \(cutoutPath)")

if args.makeUnselected {
    writePNG(unselected(cut), to: unselectedPath)
    print("wrote \(unselectedPath)")
}
