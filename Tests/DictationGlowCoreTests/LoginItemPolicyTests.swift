import XCTest
@testable import DictationGlowCore

final class LoginItemPolicyTests: XCTestCase {
  // R18. First run registers, so a restart re-arms the app without intervention.
  func testFirstRunFromApplicationsRegisters() {
    let decision = LoginItemPolicy.decide(
      status: .notRegistered, hasRegisteredBefore: false, isInstalledLocation: true)
    XCTAssertEqual(decision, .register)
  }

  // Observed on a machine with no prior record: SMAppService reports notFound rather than
  // notRegistered, so the first-run decision must not branch on notRegistered alone.
  func testFirstRunRegistersWhenTheSystemReportsNotFound() {
    let decision = LoginItemPolicy.decide(
      status: .notFound, hasRegisteredBefore: false, isInstalledLocation: true)
    XCTAssertEqual(decision, .register)
  }

  func testFirstRunRegistersWhenTheSystemReportsRequiresApproval() {
    let decision = LoginItemPolicy.decide(
      status: .requiresApproval, hasRegisteredBefore: false, isInstalledLocation: true)
    XCTAssertEqual(decision, .register)
  }

  // Apple's guidance: never re-register something the user turned off. The first-run flag is
  // what tells "never asked" apart from "asked and declined".
  func testDoesNotReRegisterAfterTheUserTurnedItOff() {
    let decision = LoginItemPolicy.decide(
      status: .notRegistered, hasRegisteredBefore: true, isInstalledLocation: true)
    XCTAssertEqual(decision, .leaveAlone)
  }

  func testDoesNotReRegisterWhenRevokedInSystemSettings() {
    let decision = LoginItemPolicy.decide(
      status: .requiresApproval, hasRegisteredBefore: true, isInstalledLocation: true)
    XCTAssertEqual(decision, .leaveAlone)
  }

  func testAlreadyEnabledNeedsNothing() {
    let decision = LoginItemPolicy.decide(
      status: .enabled, hasRegisteredBefore: true, isInstalledLocation: true)
    XCTAssertEqual(decision, .leaveAlone)
  }

  // R17. A build-tree copy must not touch the record: reading status from it repoints the
  // record's URL at whichever copy performed the read.
  func testNeverRegistersFromOutsideTheInstalledLocation() {
    for status in [LoginItemPolicy.Status.notRegistered, .requiresApproval, .enabled] {
      XCTAssertEqual(
        LoginItemPolicy.decide(
          status: status, hasRegisteredBefore: false, isInstalledLocation: false),
        .leaveAlone,
        "a copy outside /Applications must not write the login-item record")
    }
  }

  // Anything other than .enabled reads as off; the failure values are inconsistent in the
  // field, so the toggle must branch on enabled rather than on a specific failure.
  func testOnlyEnabledCountsAsOn() {
    XCTAssertTrue(LoginItemPolicy.isOn(.enabled))
    XCTAssertFalse(LoginItemPolicy.isOn(.notRegistered))
    XCTAssertFalse(LoginItemPolicy.isOn(.requiresApproval))
    XCTAssertFalse(LoginItemPolicy.isOn(.notFound))
  }
}
