// swift-tools-version:5.9
// PianoKit = the model without UI (pieces, MIDI, quiz, statistics), PianoUI = the SwiftUI screens shared by
// iPhone, iPad and Mac, DesignKit = the design tokens and dashboard tiles.
import PackageDescription

let package = Package(
    name: "Piano",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PianoKit", targets: ["PianoKit"]),
               .library(name: "PianoUI", targets: ["PianoUI"])],
    targets: [
        .target(name: "DesignKit"),
        .target(name: "PianoKit"),
        .target(name: "PianoUI", dependencies: ["PianoKit", "DesignKit"]),
        .testTarget(name: "PianoKitTests", dependencies: ["PianoKit"],
                    resources: [.copy("Fixtures")]),
    ]
)
