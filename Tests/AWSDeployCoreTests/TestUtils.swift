//
//  TestUtils.swift
//
//
//  Created by Joel Saltzman on 4/7/21.
//

import Foundation
import XCTest
import Logging
import LogKit
@testable import AWSDeployCore

enum ExamplePackage {
    static var name = "ExamplePackage"
    static var library = "Core"
    static var executableOne = "executableOne"
    static var executableTwo = "executableTwo"
    static var executableThree = "executableThree"
    static var executables = [ExamplePackage.executableOne, ExamplePackage.executableTwo, ExamplePackage.executableThree]
}

func createTempPackage(includeSource: Bool = true, includeDockerfile: Bool = true) throws -> String {
    let packageManifest = """
    // swift-tools-version:5.3
    import PackageDescription

    let package = Package(
        name: "\(ExamplePackage.name)",
        products: [
            // Products define the executables and libraries a package produces, and make them visible to other packages.
            .library(
                name: "\(ExamplePackage.library)",
                targets: ["\(ExamplePackage.library)"]),
            .executable(
                name: "\(ExamplePackage.executableOne)",
                targets: ["\(ExamplePackage.executableOne)"]),
            .executable(
                name: "\(ExamplePackage.executableTwo)",
                targets: ["\(ExamplePackage.executableTwo)"]),
            .executable(
                name: "\(ExamplePackage.executableThree)",
                targets: ["\(ExamplePackage.executableThree)"]),
        ],
        targets: [
            .target(
                name: "\(ExamplePackage.library)",
                dependencies: []),
            .target(
                name: "\(ExamplePackage.executableOne)",
                dependencies: []),
            .target(
                name: "\(ExamplePackage.executableTwo)",
                dependencies: []),
            .target(
                name: "\(ExamplePackage.executableThree)",
                dependencies: []),
        ]
    )

    """
    let packageDirectory = URL(fileURLWithPath: "/tmp/\(ExamplePackage.name)")
    try? FileManager.default.removeItem(at: packageDirectory)
    try FileManager.default.createDirectory(
        at: packageDirectory,
        withIntermediateDirectories: true,
        attributes: [FileAttributeKey.posixPermissions: 0o777]
    )
    let manifestURL = packageDirectory.appendingPathComponent("Package.swift")
    try packageManifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    print("Created package manifest: \(manifestURL.path) success: \(FileManager.default.fileExists(atPath: manifestURL.path))")
    try FileManager.default.setAttributes([FileAttributeKey.posixPermissions: 0o777], ofItemAtPath: manifestURL.path)
    if includeSource {
        let products = [ExamplePackage.library, ExamplePackage.executableOne, ExamplePackage.executableTwo, ExamplePackage.executableThree]
        for product in products {
            let sourcesURL = packageDirectory.appendingPathComponent("Sources")
            let productDirectory = sourcesURL.appendingPathComponent(product)
            try FileManager.default.createDirectory(
                at: productDirectory,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.posixPermissions: 0o777]
            )
            let source = "print(\"Hello Test Package!\")"
            let sourceFileURL = productDirectory.appendingPathComponent("main.swift")
            try source.write(to: sourceFileURL, atomically: true, encoding: .utf8)
            print("Created source file: \(sourceFileURL) success: \(FileManager.default.fileExists(atPath: sourceFileURL.path))")
        }
    }
    if includeDockerfile {
        // Create the Dockerfile
        let dockerfile = packageDirectory.appendingPathComponent("Dockerfile")
        let contents = "FROM \(BuildInDocker.DockerConfig.imageName)\nRUN yum -y install zip"
        try contents.write(to: dockerfile, atomically: true, encoding: .utf8)
        print("Created dockerfile: \(dockerfile.path) success: \(FileManager.default.fileExists(atPath: dockerfile.path))")
    }
    let _: String = try ShellExecutor.run("/usr/local/bin/docker rm \(BuildInDocker.DockerConfig.containerName) || true")
    return packageDirectory.path
}

// MARK: - XCTestCase
func XCTAssertString(_ result: String, contains search: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(result.contains(search), "\"\(search)\" was not found in String: \(result)", file: file, line: line)
}

public func XCTFail(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    XCTFail("Unexpected error: \(error)", file: file, line: line)
}

// MARK: - LogCollector
extension LogCollector.Logs {
    static func stubMessage(level: Logger.Level, message: String) -> LogCollector.Logs {
        let logs = LogCollector.Logs()
        logs.append(level: level, message: .init(stringLiteral: "\(message)"), metadata: nil)
        return logs
    }
}

