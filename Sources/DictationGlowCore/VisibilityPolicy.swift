import Foundation

/// What the overlay can be asked to do, so the policy can be tested without a window server.
public protocol BandControlling: AnyObject {
  func show()
  func hide()
  var isVisible: Bool { get }
}

/// Binds the band's visibility to the machine's state and to nothing else.
///
/// Fails closed by construction rather than by a check: the policy has no audio input, no
/// process list, and no timer of its own. The only thing that can raise the band is a
/// `.listening` state, which only a Dictation-specific notification produces. A live
/// microphone the app cannot attribute to Dictation has no path to this class at all.
public final class VisibilityPolicy {
  private let band: BandControlling

  public init(band: BandControlling) {
    self.band = band
  }

  public func apply(_ state: EdgeMachine.State) {
    switch state {
    case .listening:
      guard !band.isVisible else { return }
      band.show()
    case .idle:
      guard band.isVisible else { return }
      band.hide()
    }
  }
}
