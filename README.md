# hdrmerge-swift

A Swift port of [HDRMerge](https://github.com/jcelaya/hdrmerge): merge a set of
RAW exposures into **one Bayer (CFA) DNG** — the output stays a mosaic, it is
never demosaiced.

```
hdrmerge-swift merge -o out.dng a.dng b.dng c.dng
hdrmerge-swift inspect out.dng
```

License: **GPL-3.0-or-later** (see `LICENSE`). HDRMerge is © 2012 Javier Celaya;
this port keeps the same license and the same algorithm structure.

## Status

| Piece | State |
|---|---|
| DNG / TIFF reader (CFA plane, tags, strips + tiles) | works |
| Lossless JPEG (Compression = 7, 1…4 components, 1×1 sampling) | works |
| Uncompressed (Compression = 1) | works |
| Deflate (Compression = 8), JPEG XL, BigTIFF, CR3/NEF/ARW/RAF | not yet |
| Ward MTB alignment (6-level pyramid) | works |
| Exposure-ratio estimation, saturation mask, feather + compose | works |
| CFA DNG writer (16-bit integer, 32-bit float) | works |
| Qt GUI, mask editing, preview | no (out of scope for now) |

## Verification (this machine, 2026-11-11)

* **Decoder bit-exactness** — `L1030433.dng` (Leica SL3, 9536 × 6344, LJPEG
  stored as two interleaved components) decoded by this tool compares
  **byte-identical** to LibRaw 0.22.3's `unprocessed_raw` output (120,992,787 B
  PGM, `cmp` clean).
* **Merge** — a synthetic 4-stop bracket built from `P4270052.dng` (YI M1,
  5200 × 3902) recovers the exposure ratio as **4.000** and reproduces the
  analytic prediction to **≤ 1 LSB** (mean |Δ| 0.25, max 0) over 2.25 M samples.
* **Alignment** — a synthetic 6 px / 4 px shift is recovered, the canvas is
  cropped to 5194 × 3898, and the merged mosaic still matches the analytic
  prediction to ≤ 1 LSB.
* Output opens in LibRaw (`raw-identify`: "YI M1 image") and in ImageIO.

Timings (M-series, release build): decode 60 MP ≈ 2.8 s; merge 20 MP from two
frames ≈ 3.1 s.

## Build

```
swift build -c release
.build/release/hdrmerge-swift --help
```

No third-party dependencies: the RAW path is pure Swift (no LibRaw), so the
binary has no runtime deps beyond the system frameworks.

## Commands

```
inspect <file.dng>...              print geometry, CFA pattern, black/white, EXIF exposure
decode  <in.dng> <out.pgm>         16-bit PGM of the raw mosaic (used as a decoder oracle)
merge   -o out.dng [options] ...   merge 1..n frames into one CFA DNG
        -b 16|32                   output bits per sample (default 32 = float DNG)
        --feather N                mask feather radius (default 3)
        --white N                  override the white/saturation level
synth   <in> <out> <divisor> [dx dy]   test aid: fake a shorter exposure, optionally shifted
```

## Deviations from upstream HDRMerge

See `PORTING.md`. Short version: exposure ratio uses least squares instead of
the penalised spline response fit (identical for linear sensor data), and the
mask fattening filter is square rather than a disk. Everything else follows
`Image.cpp` / `ImageStack.cpp` / `DngFloatWriter.cpp` closely, including the
"normalise the brightest pixel to the white level" step in `compose()`.
