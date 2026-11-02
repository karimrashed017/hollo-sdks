// swift-tools-version: 5.10
// 5.10 keeps the Swift 5 language mode, so apps on Swift 6 strict concurrency
// can still build us; the code itself keeps UI and state on the main actor.
import PackageDescription

// At the root of the public SDK repo, because Swift Package Manager only
// installs packages whose manifest is at the root of a git repository.

let package = Package(
    name: "Hollo",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Hollo", targets: ["Hollo"]),
    ],
    targets: [
        .target(
            name: "Hollo",
            path: "ios/Sources/Hollo",
            // Apple reads the privacy manifest from the bundle root, so copy
            // it as is rather than processing it.
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "HolloTests",
            dependencies: ["Hollo"],
            path: "ios/Tests/HolloTests"
        ),
    ]
)
