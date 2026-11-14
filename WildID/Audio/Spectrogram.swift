import Accelerate
import SwiftUI
import UIKit
import os

/// Short-time Fourier transform producing spectrogram columns (frequency on the vertical axis,
/// time on the horizontal axis, intensity as brightness).
///
/// - FFT size 1024 at 48 kHz (46.9 Hz per bin), Hann window, hop 600 samples (80 columns/second).
/// - Shows 0–12 kHz, the range that contains almost all bird, frog, mammal and insect calls
///   that phone microphones capture well.
/// - Intensity is in decibels relative to an adaptive per-frequency noise floor, which keeps
///   steady background noise (wind, traffic hum) faint and makes calls stand out.
final class SpectrogramProcessor: @unchecked Sendable {
    static let fftSize = 1024
    static let hop = 600
    static let maxFrequency: Double = 12_000
    static let columnsPerSecond = AudioCaptureEngine.analysisSampleRate / Double(hop)

    let rows: Int
    let capacity: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var pending: [Float] = []
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var noiseFloor: [Float]
    private var peakDB: Float = -40

    // Ring buffer of columns, column-major (each column contiguous, low frequency first).
    private var ring: [UInt8]
    private var writeIndex = 0
    private(set) var totalColumns = 0
    private let lock = OSAllocatedUnfairLock()

    init(seconds: Double = 10) {
        let bins = Self.fftSize / 2
        rows = Int(Double(bins) * Self.maxFrequency / (AudioCaptureEngine.analysisSampleRate / 2))   // 256
        capacity = Int(seconds * Self.columnsPerSecond)
        log2n = vDSP_Length(log2(Double(Self.fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        real = [Float](repeating: 0, count: bins)
        imag = [Float](repeating: 0, count: bins)
        magnitudes = [Float](repeating: 0, count: bins)
        noiseFloor = [Float](repeating: -90, count: rows)
        ring = [UInt8](repeating: 0, count: rows * capacity)
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func reset(keepNoiseFloor: Bool = false) {
        lock.withLockUnchecked {
            ring = [UInt8](repeating: 0, count: rows * capacity)
            writeIndex = 0
            totalColumns = 0
        }
        pending.removeAll()
        if !keepNoiseFloor { noiseFloor = [Float](repeating: -90, count: rows) }
    }

    /// Feed mono samples (any length). Must be called from a single thread.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        var offset = 0
        while pending.count - offset >= Self.fftSize {
            pending.withUnsafeBufferPointer { buf in
                computeColumn(UnsafeBufferPointer(rebasing: buf[offset..<(offset + Self.fftSize)]))
            }
            offset += Self.hop
        }
        if offset > 0 { pending.removeFirst(offset) }
    }

    private func computeColumn(_ frame: UnsafeBufferPointer<Float>) {
        let n = Self.fftSize
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(n))
        let half = n / 2
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // Power -> dB
        let decibels = vDSP.multiply(10, vForce.log10(vDSP.add(1e-12, magnitudes)))

        var column = [UInt8](repeating: 0, count: rows)
        var frameMax: Float = -200
        for r in 0..<rows {
            let db = decibels[r]
            frameMax = max(frameMax, db)
            // Asymmetric tracking: the floor falls quickly and rises slowly, so it follows the
            // background noise but not transient calls.
            let floor = noiseFloor[r]
            noiseFloor[r] = db < floor ? floor + (db - floor) * 0.15 : floor + (db - floor) * 0.004
            let snr = db - noiseFloor[r] - 4
            var v = max(0, min(1, snr / 30))
            v = powf(v, 0.8)
            // Very low frequencies (<150 Hz) are mostly handling noise and wind.
            if r < 3 { v *= 0.3 }
            column[r] = UInt8(v * 255)
        }
        peakDB = max(peakDB * 0.999 + frameMax * 0.001, frameMax)
        lock.withLockUnchecked {
            let base = writeIndex * rows
            ring.replaceSubrange(base..<(base + rows), with: column)
            writeIndex = (writeIndex + 1) % capacity
            totalColumns += 1
        }
    }

    /// Copies the visible spectrogram into a row-major grayscale bitmap (high frequencies on top).
    /// Returns the number of columns available (≤ capacity).
    func snapshot(into pixels: inout [UInt8], lut: [UInt8]) -> Int {
        lock.withLockUnchecked {
            let available = min(totalColumns, capacity)
            let start = (writeIndex - available + capacity) % capacity
            let blank = lut[0]
            for i in 0..<pixels.count { pixels[i] = blank }
            let leftPad = capacity - available   // new data scrolls in from the right
            ring.withUnsafeBufferPointer { src in
                pixels.withUnsafeMutableBufferPointer { dst in
                    for c in 0..<available {
                        let col = (start + c) % capacity
                        let x = leftPad + c
                        let colBase = col * rows
                        for r in 0..<rows {
                            dst[(rows - 1 - r) * capacity + x] = lut[Int(src[colBase + r])]
                        }
                    }
                }
            }
            return available
        }
    }
}

/// UIKit-backed view that redraws the scrolling spectrogram at display rate.
struct LiveSpectrogramView: UIViewRepresentable {
    let processor: SpectrogramProcessor
    var isActive: Bool

    func makeUIView(context: Context) -> SpectrogramUIView {
        let view = SpectrogramUIView(processor: processor)
        return view
    }

    func updateUIView(_ uiView: SpectrogramUIView, context: Context) {
        uiView.setActive(isActive)
    }

    static func dismantleUIView(_ uiView: SpectrogramUIView, coordinator: ()) {
        uiView.setActive(false)
    }
}

/// WildID's "night vision" colour map: deep teal background, mint signal, warm highlights.
enum SpectrogramPalette {
    static let identity: [UInt8] = (0..<256).map { UInt8($0) }

    /// 256 RGBA colours (premultiplied, little-endian ABGR as UInt32 for RGBA byte order).
    static let rgba: [UInt32] = (0..<256).map { i in
        let v = pow(Double(i) / 255, 0.85)
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (9, 34, 33)), (0.35, (22, 110, 96)), (0.65, (88, 226, 182)), (0.85, (190, 245, 190)), (1.00, (255, 236, 160)),
        ]
        var c = stops.last!.1
        for k in 1..<stops.count where v <= stops[k].0 {
            let (a, ca) = stops[k - 1], (b, cb) = stops[k]
            let t = (v - a) / (b - a)
            c = (ca.0 + (cb.0 - ca.0) * t, ca.1 + (cb.1 - ca.1) * t, ca.2 + (cb.2 - ca.2) * t)
            break
        }
        return UInt32(255) << 24 | UInt32(c.2) << 16 | UInt32(c.1) << 8 | UInt32(c.0)
    }

    static func image(gray: [UInt8], width: Int, height: Int, rgbaBuffer: inout [UInt32]) -> CGImage? {
        if rgbaBuffer.count != gray.count { rgbaBuffer = [UInt32](repeating: 0, count: gray.count) }
        gray.withUnsafeBufferPointer { g in
            rgbaBuffer.withUnsafeMutableBufferPointer { out in
                for i in 0..<g.count { out[i] = rgba[Int(g[i])] }
            }
        }
        let data = rgbaBuffer.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

final class SpectrogramUIView: UIView {
    private let processor: SpectrogramProcessor
    private var link: CADisplayLink?
    private var pixels: [UInt8]
    private var rgba: [UInt32] = []
    private var lastColumns = -1

    init(processor: SpectrogramProcessor) {
        self.processor = processor
        self.pixels = [UInt8](repeating: 0, count: processor.rows * processor.capacity)
        super.init(frame: .zero)
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .trilinear
        backgroundColor = UIColor(red: 9 / 255, green: 34 / 255, blue: 33 / 255, alpha: 1)
        isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ active: Bool) {
        if active, link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            l.add(to: .main, forMode: .common)
            link = l
        } else if !active {
            link?.invalidate()
            link = nil
        }
        render(force: true)
    }

    @objc private func tick() { render(force: false) }

    private func render(force: Bool) {
        let total = processor.totalColumns
        if !force && total == lastColumns { return }
        lastColumns = total
        _ = processor.snapshot(into: &pixels, lut: SpectrogramPalette.identity)
        guard let image = SpectrogramPalette.image(gray: pixels, width: processor.capacity, height: processor.rows, rgbaBuffer: &rgba) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }
}

/// Renders a static spectrogram for a span of a saved recording (used in session playback).
enum StaticSpectrogram {
    static func image(samples: [Float], dark: Bool, height: Int = 128) -> CGImage? {
        let p = SpectrogramProcessor(seconds: Double(samples.count) / AudioCaptureEngine.analysisSampleRate + 0.1)
        // Warm the noise floor with the first second so the image doesn't start bright.
        samples.prefix(48_000).withUnsafeBufferPointer { p.append($0) }
        p.reset(keepNoiseFloor: true)
        samples.withUnsafeBufferPointer { p.append($0) }
        var pixels = [UInt8](repeating: 0, count: p.rows * p.capacity)
        _ = p.snapshot(into: &pixels, lut: SpectrogramPalette.identity)
        var buffer: [UInt32] = []
        return SpectrogramPalette.image(gray: pixels, width: p.capacity, height: p.rows, rgbaBuffer: &buffer)
    }
}
