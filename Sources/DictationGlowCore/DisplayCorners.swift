import CoreGraphics
import Foundation

/// The radius macOS rounds a display's corners to, in points, read from the window server.
///
/// A display's corner radius has no public API. `SLSDisplayGetCornerRadii` in SkyLight is the
/// one thing on the system that reports it, and its answer is in points of the display's
/// current mode -- the same units the band is laid out in, and it changes with the scaled
/// resolution, which is why it is read on every rebuild rather than once.
///
/// Signature taken from the instruction stream, since there is no header: the display id
/// arrives in `x0` and four `double *` out parameters in `x1`-`x4`, each written only if
/// non-null, and the return is a `CGError` -- `kCGErrorFailure` for a display id the window
/// server does not know. Passing fewer than four pointers crashes; the function stores
/// through whatever the argument registers happen to hold.
///
/// Weakly bound and failure is ordinary: a build of macOS without the symbol, or a display
/// the call refuses, reports no radius and the band keeps the square corner it has always
/// drawn.
enum DisplayCorners {
  private typealias GetCornerRadii = @convention(c) (
    UInt32, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>,
    UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>
  ) -> Int32

  private static let getCornerRadii: GetCornerRadii? = {
    guard
      let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
      let symbol = dlsym(skyLight, "SLSDisplayGetCornerRadii")
    else { return nil }
    return unsafeBitCast(symbol, to: GetCornerRadii.self)
  }()

  /// The four radii as reported, in whatever order the four out parameters are in. Which
  /// argument is which corner is not recoverable from the instruction stream and does not
  /// matter here -- see `BandGeometry.cornerRadius(forReportedRadii:)`, which takes the
  /// largest and applies it to all four.
  static func reportedRadii(for displayID: CGDirectDisplayID) -> [CGFloat] {
    guard let getCornerRadii else { return [] }
    var first = 0.0, second = 0.0, third = 0.0, fourth = 0.0
    guard getCornerRadii(displayID, &first, &second, &third, &fourth) == 0 else { return [] }
    return [first, second, third, fourth].map { CGFloat($0) }
  }
}
