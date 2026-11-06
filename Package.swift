// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GrokNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GrokNotes", path: "Sources/GrokNotes"),
        .testTarget(name: "GrokNotesTests", dependencies: ["GrokNotes"], path: "Tests/GrokNotesTests"),
    ]
)
