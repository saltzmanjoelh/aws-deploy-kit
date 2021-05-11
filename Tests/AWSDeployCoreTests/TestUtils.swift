//
//  TestUtils.swift
//
//
//  Created by Joel Saltzman on 4/7/21.
//

import Foundation
import XCTest
@testable import AWSDeployCore

enum TestPackage {
    static var name = "TestPackage"
    static var library = "TestPackage"
    static var executable = "TestExecutable"
    static var skipTarget = "SkipMe"
}

func createTempPackage(includeSource: Bool = true, includeDockerfile: Bool = true) throws -> String {
    let package = """
    // swift-tools-version:5.3
    import PackageDescription

    let package = Package(
        name: "\(TestPackage.name)",
        products: [
            // Products define the executables and libraries a package produces, and make them visible to other packages.
            .library(
                name: "\(TestPackage.library)",
                targets: ["\(TestPackage.library)"]),
            .executable(
                name: "\(TestPackage.executable)",
                targets: ["\(TestPackage.executable)"]),
        ],
        targets: [
            .target(
                name: "\(TestPackage.library)",
                dependencies: []),
            .target(
                name: "\(TestPackage.executable)",
                dependencies: []),
        ]
    )

    """
    let directoryPath = "/tmp/\(TestPackage.name)"
    let directory = URL(fileURLWithPath: directoryPath)
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [FileAttributeKey.posixPermissions: 0o777]
    )
    let scriptPath = "\(directoryPath)/Package.swift"
    let fileURL = URL(fileURLWithPath: scriptPath)
    try (package as NSString).write(
        to: fileURL,
        atomically: true,
        encoding: String.Encoding.utf8.rawValue
    )
    try FileManager.default.setAttributes([FileAttributeKey.posixPermissions: 0o777], ofItemAtPath: scriptPath)
    if includeSource {
        let products = [TestPackage.library, TestPackage.executable, TestPackage.skipTarget]
        for product in products {
            let sourcesURL = directory.appendingPathComponent("Sources")
            let productDirectory = sourcesURL.appendingPathComponent(product)
            try FileManager.default.createDirectory(
                at: productDirectory,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.posixPermissions: 0o777]
            )
            let source = "print(\"Hello Test Package!\")"
            let sourceFileURL = productDirectory.appendingPathComponent("main.swift")
            try (source as NSString).write(
                to: sourceFileURL,
                atomically: true,
                encoding: String.Encoding.utf8.rawValue
            )
        }
    }
    if includeDockerfile {
        // Create the Dockerfile
        let dockerFile = "FROM \(BuildInDocker.DockerConfig.imageName)\nRUN yum -y install zip"
        try (dockerFile as NSString).write(
            toFile: URL(string: directoryPath)!.appendingPathComponent("Dockerfile").absoluteString,
            atomically: true,
            encoding: String.Encoding.utf8.rawValue
        )
    }
    try ShellExecutor.run("/usr/local/bin/docker rm \(BuildInDocker.DockerConfig.containerName) || true")
    return directoryPath
}

// MARK: - XCTestCase
func XCTAssertString(_ result: String, contains search: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(result.contains(search), "\"\(search)\" was not found in String: \(result)", file: file, line: line)
}

public func XCTFail(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    XCTFail("Unexpected error: \(error)", file: file, line: line)
}
