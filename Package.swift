// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GradeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "GradeCore", targets: ["GradeCore"])],
    targets: [
        .target(name: "GradeCore", path: "GradeSpace/Native", exclude: ["GradeSpaceApp.swift"], sources: ["Journal.swift", "JournalStore.swift"]),
        .testTarget(name: "GradeCoreTests", dependencies: ["GradeCore"], path: "GradeSpaceTests")
    ]
)

