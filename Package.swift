// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EkaScribeSDK",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "EkaScribeSDK", targets: ["EkaScribeSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/aws-amplify/aws-sdk-ios-spm.git", from: "2.36.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", exact: "1.17.0"),
        .package(url: "https://github.com/gfreezy/libfvad.git", from: "1.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0")
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
                "Alamofire"
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
