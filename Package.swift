// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "aws-deploy-kit",
    platforms: [
        .macOS(.v10_12)
    ],
    products: [
        .library(
            name: "AWSDeployCore",
            targets: ["AWSDeployCore"]
        ),
        .executable(
            name: "aws-deploy",
            targets: ["aws-deploy"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/saltzmanjoelh/mocking", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/saltzmanjoelh/log-kit", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "0.5.0")),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime", .branch("main")),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events", .branch("main")),
        .package(url: "https://github.com/apple/swift-log", .upToNextMajor(from: "1.4.2")),
        .package(url: "https://github.com/apple/swift-nio", .upToNextMajor(from: "2.32.1")),
        .package(url: "https://github.com/soto-project/soto", .upToNextMajor(from: "5.8.1")),
        .package(url: "https://github.com/soto-project/soto-core", .upToNextMajor(from: "5.6.0")),
    ],
    targets: [
        .target(
            name: "AWSDeployCore",
            dependencies: [
                .product(name: "Mocking", package: "mocking"),
                .product(name: "LogKit", package: "log-kit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SotoSTS", package: "soto"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoIAM", package: "soto"),
                .product(name: "SotoLambda", package: "soto"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        ),
        .testTarget(
            name: "AWSDeployCoreTests",
            dependencies: [
                "AWSDeployCore",
                .product(name: "Mocking", package: "mocking"),
                .product(name: "LogKit", package: "log-kit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SotoSTS", package: "soto"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoIAM", package: "soto"),
                .product(name: "SotoLambda", package: "soto"),
                .product(name: "SotoTestUtils", package: "soto-core"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        ),
        .target(
            name: "aws-deploy",
            dependencies: [
                "AWSDeployCore",
                .product(name: "Mocking", package: "mocking"),
                .product(name: "LogKit", package: "log-kit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SotoSTS", package: "soto"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoIAM", package: "soto"),
                .product(name: "SotoLambda", package: "soto"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        ),
    ]
)
