import Foundation

/// Decides whether to touch the login-item record, separately from touching it.
///
/// Registration is a write to state the user owns, so it happens once and never again.
/// Apple's guidance is explicit that an app must not re-register something the user disabled
/// in System Settings; the first-run flag is what distinguishes "never asked" from "asked and
/// then turned off", which the status alone cannot say.
///
/// Reported status after a user revokes consent is inconsistent in the field -- the header
/// says `requiresApproval`, reports in the wild show `notFound` -- so every consumer branches
/// on `enabled` rather than on a particular failure value.
public enum LoginItemPolicy {
  /// Mirrors `SMAppService.Status` so the decision is testable without ServiceManagement.
  public enum Status: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
  }

  public enum Decision: Equatable, Sendable {
    case register
    case leaveAlone
  }

  public static func decide(
    status: Status, hasRegisteredBefore: Bool, isInstalledLocation: Bool
  ) -> Decision {
    // A build-tree or worktree copy must not write the record at all: the record keys on the
    // bundle, and reading status from a second copy repoints it at whichever copy read it.
    guard isInstalledLocation else { return .leaveAlone }
    guard !hasRegisteredBefore else { return .leaveAlone }
    // Branch on `enabled`, never on a particular failure value. A machine that has never
    // registered this app reports `notFound` here rather than `notRegistered`, and the value
    // after a user revokes consent differs between the header and the field, so any
    // not-enabled state on a first run means "never asked".
    guard !isOn(status) else { return .leaveAlone }
    return .register
  }

  public static func isOn(_ status: Status) -> Bool { status == .enabled }
}
