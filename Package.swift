// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EkaScribeSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "EkaScribeSDK", targets: ["EkaScribeSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", branch: "master"),
        .package(url: "https://github.com/aws-amplify/aws-sdk-ios-spm.git", .upToNextMajor(from: "2.36.6")),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", exact: "1.17.0"),
        .package(url: "https://github.com/gfreezy/libfvad.git", branch: "main"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.10.2")),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "EkaScribeSDK",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "AWSCore", package: "aws-sdk-ios-spm"),
                .product(name: "AWSS3", package: "aws-sdk-ios-spm"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                "libfvad",
                "Alamofire",
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/EkaScribeSDK"
        ),
        .testTarget(
            name: "EkaScribeSDKTests",
            dependencies: ["EkaScribeSDK"],
            path: "Tests/EkaScribeSDKTests"
        )
    ]
)
