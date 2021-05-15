// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AWSDeployKit",
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
        .package(url: "https://github.com/saltzmanjoelh/LogKit", .branch("main")),
        .package(url: "https://github.com/apple/swift-argument-parser", .branch("main")),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .branch("main")),
        .package(url: "https://github.com/apple/swift-log", .branch("main")),
        .package(url: "https://github.com/apple/swift-nio", .branch("main")),
        .package(url: "https://github.com/soto-project/soto", .branch("main")),
        .package(url: "https://github.com/soto-project/soto-core", .branch("main")),
    ],
    targets: [
        .target(
            name: "AWSDeployCore",
            dependencies: [
                .product(name: "LogKit", package: "LogKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoLambda", package: "soto"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-runtime"),
            ],
            resources: [.process("scripts")]
        ),
        .testTarget(
            name: "AWSDeployCoreTests",
            dependencies: [
                "AWSDeployCore",
                .product(name: "LogKit", package: "LogKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoLambda", package: "soto"),
                .product(name: "SotoTestUtils", package: "soto-core"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-runtime"),
            ]
        ),
        .target(
            name: "aws-deploy",
            dependencies: [
                "AWSDeployCore",
                .product(name: "LogKit", package: "LogKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoLambda", package: "soto"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-runtime"),
            ]
        ),
    ]
)
