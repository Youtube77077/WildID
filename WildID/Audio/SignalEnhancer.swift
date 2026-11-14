import Accelerate
import Foundation

/// Makes faint animal sounds easier for the classifier to pick out of background noise.
///
/// Sound ID runs BirdNET twice on every 3-second window: once on the untouched audio (so loud,
/// low-pitched calls such as owls, deer or bitterns keep their full spectrum) and once on an
/// *enhanced* copy produced here, and keeps the stronger score for each species. The enhanced
/// copy has
///
///  1. a 4th-order Butterworth high-pass filter (two cascaded biquads) that removes wind
///     rumble, traffic hum and phone-handling thumps below the cutoff, and
///  2. automatic gain: the filtered window is scaled so its loudest moments reach a fixed
///     level, lifting a distant call that is 30–40 dB below the room noise into the range the
///     model was trained on. The boost is capped so pure silence is not blown up into hiss.
///
/// Everything here is deterministic signal processing (no generative model) and runs on the
/// inference queue, never on the audio capture thread.
enum SignalEnhancer {
    /// Cutoff of the wind/rumble filter in Hz.
    static let highPassCutoff: Double = 250
    /// Target level for the loudest part of the enhanced window (≈ −12 dBFS).
    static let targetPeak: Float = 0.25
    /// Maximum boost (≈ +36 dB).
    static let maxGain: Float = 64

    /// Biquad coefficients [b0, b1, b2, a1, a2] of a 2nd-order Butterworth high-pass section
    /// (RBJ cookbook form, a0 normalised to 1).
    static func highPassCoefficients(cutoff: Double, sampleRate: Double, q: Double) -> [Double] {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        let b0 = (1 + cosw) / 2 / a0
        let b1 = -(1 + cosw) / a0
        let b2 = (1 + cosw) / 2 / a0
        let a1 = -2 * cosw / a0
        let a2 = (1 - alpha) / a0
        return [b0, b1, b2, a1, a2]
    }

    /// The two Q values of a 4th-order Butterworth filter split into two biquads.
    private static let butterworthQs: [Double] = [0.541_196_1, 1.306_563_0]

    /// Applies the high-pass filter. Returns a new array of the same length.
    static func highPass(_ samples: [Float], sampleRate: Double = AudioCaptureEngine.analysisSampleRate,
                         cutoff: Double = highPassCutoff) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var coefficients: [Double] = []
        for q in butterworthQs { coefficients += highPassCoefficients(cutoff: cutoff, sampleRate: sampleRate, q: q) }
        let sections = vDSP_Length(butterworthQs.count)
        guard let setup = vDSP_biquad_CreateSetup(coefficients, sections) else { return samples }
        defer { vDSP_biquad_DestroySetup(setup) }
        var delay = [Float](repeating: 0, count: 2 * Int(sections) + 2)
        var output = [Float](repeating: 0, count: samples.count)
        vDSP_biquad(setup, &delay, samples, 1, &output, 1, vDSP_Length(samples.count))
        return output
    }

    /// A robust "loudest moment" estimate: the 99.5th percentile of |x| over short blocks, so a
    /// single click does not stop the rest of the window from being boosted.
    static func robustPeak(_ samples: [Float]) -> Float {
        let block = 480   // 10 ms at 48 kHz
        guard samples.count >= block else {
            var m: Float = 0
            vDSP_maxmgv(samples, 1, &m, vDSP_Length(samples.count))
            return m
        }
        var rmsValues: [Float] = []
        rmsValues.reserveCapacity(samples.count / block)
        samples.withUnsafeBufferPointer { p in
            var i = 0
            while i + block <= p.count {
                var rms: Float = 0
                vDSP_rmsqv(p.baseAddress! + i, 1, &rms, vDSP_Length(block))
                rmsValues.append(rms)
                i += block
            }
        }
        rmsValues.sort()
        let idx = min(rmsValues.count - 1, Int(Double(rmsValues.count) * 0.995))
        // RMS of a block is ~0.7 × its peak for tonal sounds; convert back to a peak estimate.
        return rmsValues[idx] * 1.41
    }

    /// The gain that brings `peak` to `targetPeak`, never attenuating and never above `maxGain`.
    static func gain(forPeak peak: Float) -> Float {
        guard peak > 1e-7 else { return 1 }
        return min(maxGain, max(1, targetPeak / peak))
    }

    /// High-pass + automatic gain. Output is clipped to [-1, 1].
    static func enhance(_ samples: [Float]) -> [Float] {
        var filtered = highPass(samples)
        let g = gain(forPeak: robustPeak(filtered))
        if g > 1.0001 { filtered = vDSP.multiply(g, filtered) }
        return vDSP.clip(filtered, to: -1...1)
    }
}
