//
//  main.swift
//  hdrmerge-swift
//
//  Command line front end. GPLv3 — a Swift port of HDRMerge (© 2012 Javier Celaya).
//

import Foundation
import HDRMergeCore

func usage() {
    print("""
    hdrmerge-swift — merge several RAW exposures into one Bayer (CFA) DNG

    usage:
      hdrmerge-swift inspect <file.dng> ...        print decoded metadata
      hdrmerge-swift decode <in.dng> <out.pgm>     write raw CFA samples (16-bit PGM)
      hdrmerge-swift synth <in.dng> <out.dng> <divisor> [dx dy]
                                                   fake a shorter exposure (testing aid)
      hdrmerge-swift merge -o out.dng [options] in1.dng in2.dng ...
        -b 16|32        output bits per sample (default 32 = float DNG)
        --feather N     mask feather radius (default 3)
        --white N       override white level
    """)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage(); exit(2) }

switch cmd {
case "inspect":
    for path in args.dropFirst() {
        let url = URL(fileURLWithPath: path)
        do {
            let f = try DNGReader.read(url: url)
            let cfa = f.cfaPattern.map { ["R", "G", "B", "G2"][min(Int($0), 3)] }.joined()
            print("""
            \(url.lastPathComponent)
              camera        \(f.make) \(f.model)
              raw size      \(f.fullWidth) x \(f.fullHeight)  (active \(f.activeWidth)x\(f.activeHeight) @ \(f.activeLeft),\(f.activeTop))
              crop          \(f.cropWidth) x \(f.cropHeight) @ \(f.cropX),\(f.cropY)
              CFA           \(f.cfaRows)x\(f.cfaCols)  \(cfa)
              black         \(f.blackLevel.map { String(format: "%.1f", $0) }.joined(separator: ", "))
              white         \(f.whiteLevel)
              exposure      \(f.exposureTime) s   ISO \(f.iso)
              asShotNeutral \(f.asShotNeutral)
            """)
        } catch {
            FileHandle.standardError.write(Data("\(path): \(error)\n".utf8))
            exit(1)
        }
    }

case "decode":
    guard args.count >= 3 else { usage(); exit(2) }
    let url = URL(fileURLWithPath: args[1])
    let out = URL(fileURLWithPath: args[2])
    do {
        let f = try DNGReader.read(url: url)
        try DNGReader.writePGM(f, to: out)
        print("wrote \(out.path) (\(f.fullWidth)x\(f.fullHeight))")
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }

case "synth":
    guard args.count >= 4 else { usage(); exit(2) }
    let src = try DNGReader.read(url: URL(fileURLWithPath: args[1]))
    let divisor = Double(args[3]) ?? 1
    let dx = args.count > 5 ? (Int(args[4]) ?? 0) : 0
    let dy = args.count > 5 ? (Int(args[5]) ?? 0) : 0
    let black = src.blackLevel.max() ?? 0
    var values = [Float](repeating: 0, count: src.activeWidth * src.activeHeight)
    for y in 0..<src.activeHeight {
        for x in 0..<src.activeWidth {
            let sx = x - dx, sy = y - dy
            guard sx >= 0, sx < src.activeWidth, sy >= 0, sy < src.activeHeight else { continue }
            let v = (Double(src.sample(sx, sy)) - black) / divisor + black
            values[y * src.activeWidth + x] = Float(min(max(v, 0), Double(src.whiteLevel)))
        }
    }
    let m = MergedImage(width: src.activeWidth, height: src.activeHeight, values: values,
                        black: black, white: src.whiteLevel,
                        cfaPattern: src.cfaPattern, cfaRows: src.cfaRows, cfaCols: src.cfaCols,
                        offsets: [(0, 0)], referenceIndex: 1, report: [])
    try DNGWriter.write(m, source: src, bits: 16, to: URL(fileURLWithPath: args[2]))
    print("wrote \(args[2]) (\(src.activeWidth)x\(src.activeHeight), /\(divisor), shift \(dx),\(dy))")

case "merge":
    var outPath: String?
    var bits = 32
    var feather = 3
    var white: Int?
    var inputs: [String] = []
    var i = 1
    while i < args.count {
        switch args[i] {
        case "-o": outPath = args[i + 1]; i += 2
        case "-b": bits = Int(args[i + 1]) ?? 32; i += 2
        case "--feather": feather = Int(args[i + 1]) ?? 3; i += 2
        case "--white": white = Int(args[i + 1]); i += 2
        default: inputs.append(args[i]); i += 1
        }
    }
    guard let out = outPath, inputs.count >= 1 else { usage(); exit(2) }
    do {
        let frames = try inputs.map { try DNGReader.read(url: URL(fileURLWithPath: $0)) }
        var opts = MergeOptions(featherRadius: feather, customWhiteLevel: white)
        opts.featherRadius = feather
        let merged = try HDRMergeCore.merge(frames: frames, options: opts)
        for line in merged.report { print(line) }
        print("merged \(merged.width)x\(merged.height) from \(frames.count) frame(s)")
        try DNGWriter.write(merged, source: frames[0], bits: bits, to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }

default:
    usage()
    exit(2)
}
