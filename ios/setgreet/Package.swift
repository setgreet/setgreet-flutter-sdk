// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// Flutter 3.44 and later generate a `FlutterFramework` Swift package next to
// this package's symlink (ios/Flutter/ephemeral/Packages/.packages/), and the
// Flutter plugin guide declares it as a dependency. Earlier Flutter versions
// (this plugin supports Flutter 3.27 and later) do not create that package, so
// an unconditional path dependency would fail to resolve there. Declare it
// only when it is present; without it, `import Flutter` is still served by the
// generated plugin package, which is how Flutter's own plugins build.
//
// Xcode evaluates this manifest at the symlinked location, so both paths below
// point at the `.packages` directory; the `swift package` command line resolves
// the symlink first, where neither matches and the dependency is left out.
let flutterFrameworkCandidates = [
    URL(fileURLWithPath: Context.packageDirectory),
    URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
].map { $0.appendingPathComponent("../FlutterFramework").standardizedFileURL.path }
let hasFlutterFramework = flutterFrameworkCandidates.contains {
    FileManager.default.fileExists(atPath: $0)
}

var packageDependencies: [Package.Dependency] = [
    // Keep this exact version in step with ios/Frameworks (the CocoaPods path)
    // and android/build.gradle. The update-native-sdk workflow rewrites it.
    .package(url: "https://github.com/setgreet/setgreet-ios-sdk.git", exact: "1.13.0"),
]
var targetDependencies: [Target.Dependency] = [
    .product(name: "SetgreetSDK", package: "setgreet-ios-sdk"),
]
if hasFlutterFramework {
    packageDependencies.append(.package(name: "FlutterFramework", path: "../FlutterFramework"))
    targetDependencies.append(.product(name: "FlutterFramework", package: "FlutterFramework"))
}

let package = Package(
    name: "setgreet",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "setgreet", targets: ["setgreet"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "setgreet",
            dependencies: targetDependencies
        )
    ]
)
