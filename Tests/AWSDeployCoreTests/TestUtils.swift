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
import NIO
@testable import AWSDeployCore
@testable import SotoTestUtils


enum ExamplePackage {
    static var tempDirectory: String = {
//        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
//            .appendingPathComponent("tmp")
//            .path
        return "/tmp"
    }()
    static var name = "ExamplePackage"
    static var library = Product(name: "Core", type: .library)
    static var executableOne = Product(name: "executableOne", type: .executable)
    static var executableTwo = Product(name: "executableTwo", type: .executable)
    static var executableThree = Product(name: "executableThree", type: .executable)
    static var executables = [ExamplePackage.executableOne, ExamplePackage.executableTwo, ExamplePackage.executableThree]
    static var libraries = [ExamplePackage.library]
    
    static var invokeJSON = "{\"name\": \"World!\"}"
}

func tempPackageDirectory() -> URL {
    return URL(fileURLWithPath: "\(ExamplePackage.tempDirectory)/\(ExamplePackage.name)")
}
func createTempPackage(includeSource: Bool = true, includeDockerfile: Bool = true) throws -> URL {
    let packageManifest = """
    // swift-tools-version:5.3
    import PackageDescription

    let package = Package(
        name: "\(ExamplePackage.name)",
        products: [
            // Products define the executables and libraries a package produces, and make them visible to other packages.
            .library(
                name: "\(ExamplePackage.library.name)",
                targets: ["\(ExamplePackage.library.name)"]),
            .executable(
                name: "\(ExamplePackage.executableOne.name)",
                targets: ["\(ExamplePackage.executableOne.name)"]),
            .executable(
                name: "\(ExamplePackage.executableTwo.name)",
                targets: ["\(ExamplePackage.executableTwo.name)"]),
            .executable(
                name: "\(ExamplePackage.executableThree.name)",
                targets: ["\(ExamplePackage.executableThree.name)"]),
        ],
        dependencies: [ .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .branch("main")) ],
        targets: [
            .target(
                name: "\(ExamplePackage.library.name)",
                dependencies: []),
            .target(
                name: "\(ExamplePackage.executableOne.name)",
                dependencies: [ .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"), ]),
            .target(
                name: "\(ExamplePackage.executableTwo.name)",
                dependencies: [ .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"), ]),
            .target(
                name: "\(ExamplePackage.executableThree.name)",
                dependencies: [ .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"), ]),
        ]
    )

    """
    let packageDirectory = tempPackageDirectory()
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
        let libraries = [ExamplePackage.library]
        for library in libraries {
            let sourcesURL = packageDirectory.appendingPathComponent("Sources")
            let libraryDirectory = sourcesURL.appendingPathComponent(library.name)
            try FileManager.default.createDirectory(
                at: libraryDirectory,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.posixPermissions: 0o777]
            )
            let source = ""
            let sourceFileURL = libraryDirectory.appendingPathComponent("\(library.name).swift")
            try source.write(to: sourceFileURL, atomically: true, encoding: .utf8)
            print("Created source file: \(sourceFileURL) success: \(FileManager.default.fileExists(atPath: sourceFileURL.path))")
        }
        let products = [ExamplePackage.executableOne, ExamplePackage.executableTwo, ExamplePackage.executableThree]
        for product in products {
            let sourcesURL = packageDirectory.appendingPathComponent("Sources")
            let productDirectory = sourcesURL.appendingPathComponent(product.name)
            try FileManager.default.createDirectory(
                at: productDirectory,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.posixPermissions: 0o777]
            )
            let source = """
                print("Hello Test Package!")
                import AWSLambdaRuntime
                Lambda.run { (context, name: String, callback: @escaping (Result<String, Error>) -> Void) in
                  callback(.success("Hello, \\(name)"))
                }
                """
            let sourceFileURL = productDirectory.appendingPathComponent("main.swift")
            try source.write(to: sourceFileURL, atomically: true, encoding: .utf8)
            print("Created source file: \(sourceFileURL) success: \(FileManager.default.fileExists(atPath: sourceFileURL.path))")
        }
    }
    if includeDockerfile {
        // Create the Dockerfile
        let dockerfile = packageDirectory.appendingPathComponent("Dockerfile")
        let contents = "FROM \(Docker.Config.imageName)\nRUN yum install -y zip"
        try contents.write(to: dockerfile, atomically: true, encoding: .utf8)
        print("Created dockerfile: \(dockerfile.path) success: \(FileManager.default.fileExists(atPath: dockerfile.path))")
    }
    let _: String = try Shell().run("/usr/local/bin/docker rm \(Docker.Config.containerName) || true")
    return packageDirectory
}

func cleanupTestPackage() throws {
//    if FileManager.default.fileExists(atPath: ExamplePackage.tempDirectory) {
        try? FileManager.default.removeItem(atPath: ExamplePackage.tempDirectory)
//    }
}

// MARK: - XCTestCase
func XCTAssertString(_ result: String, contains search: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(result.contains(search), "\"\(search)\" was not found in String: \(result)", file: file, line: line)
}

public func XCTFail(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    XCTFail("Unexpected error: \(error)", file: file, line: line)
}

extension XCTestCase {
    func shouldTestWithLive() -> Bool {
        ProcessInfo.processInfo.environment["TEST-WITH-LIVE"] != nil
    }

    func waitToProcess(_ fixtures: [ByteBuffer], mockServices: MockServices) throws {
        var responses = fixtures
        // This is a synchronous process. Execution stops here until all fixtures are processed or it times out.
        try mockServices.awsServer.processRaw { (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            guard let result = responses.popLast() else {
                let error = AWSTestServer.ErrorType(status: 500, errorCode: "InternalFailure", message: "Unhandled request: \(request)")
                return .error(error, continueProcessing: false)
            }
            return .result(.init(httpStatus: .ok, body: result), continueProcessing: responses.count > 0)
        }
        // Once all the fixtures have been processed, it will continue.
        XCTAssertEqual(responses.count, 0, "There were fixtures left over. Not all calls were performed.")
    }
}


// MARK: - LogCollector
extension LogCollector.Logs {
    static func stubMessage(level: Logger.Level, message: String) -> LogCollector.Logs {
        let logs = LogCollector.Logs()
        logs.append(level: level, message: .init(stringLiteral: "\(message)"), metadata: nil)
        return logs
    }
    static func lddLogs() -> LogCollector.Logs {
        let logs = LogCollector.Logs()
        logs.append(level: .trace, message: "   libswiftCore.so => /usr/lib/swift/linux/libswiftCore.so (0x00007fb41d09c000)", metadata: nil)
        logs.append(level: .trace, message: "   libc.so.6 => /lib64/libc.so.6 (0x00007fb41ccf1000)", metadata: nil)
        logs.append(level: .trace, message: "   libicudataswift.so.65 => /usr/lib/swift/linux/libicudataswift.so.65 (0x00007fb41a2f1000)", metadata: nil)
        return logs
    }
}
