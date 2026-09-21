// swift-tools-version: 5.9
import PackageDescription

// The app bundle is assembled by build.sh around this package's executable product.
// DictationGlowCore holds everything that can be tested without a window server or a
// live notification stream; the executable is the thin AppKit shell around it.
let package = Package(
  name: "dictation-glow",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "DictationGlowCore"),
    .executableTarget(name: "dictation-glow", dependencies: ["DictationGlowCore"]),
    .testTarget(name: "DictationGlowCoreTests", dependencies: ["DictationGlowCore"]),
  ]
)
