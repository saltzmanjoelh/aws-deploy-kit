//
//  TestUtils.swift
//  
//
//  Created by Joel Saltzman on 4/7/21.
//

import Foundation

func createTempPackage(includeSource: Bool = false) throws -> String {
    let package = """
    // swift-tools-version:5.3
    import PackageDescription
    let package = Package(name: "TestPackage",products: [.library(name: "TestPackage",targets: ["TestPackage"]),.executable(name: "TestExecutable",targets: ["TestExecutable"]),.executable(name: "SkipMe",targets: ["SkipMe"]),],targets: [.target(name: "TestPackage",dependencies: []),.target(name: "TestExecutable",dependencies: []),.target(name: "SkipMe",dependencies: []),])
    """
    let directoryPath = "/tmp/TestPackage"
    let directory = URL(fileURLWithPath: directoryPath)
    try FileManager.default.createDirectory(at: directory,
                                            withIntermediateDirectories: true,
                                            attributes: [FileAttributeKey.posixPermissions : 0o777])
    let scriptPath = "\(directoryPath)/Package.swift"
    let fileURL = URL(fileURLWithPath: scriptPath)
    try (package as NSString).write(to: fileURL,
                                   atomically: true,
                                   encoding: String.Encoding.utf8.rawValue)
    try FileManager.default.setAttributes([FileAttributeKey.posixPermissions : 0o777], ofItemAtPath: scriptPath)
    if includeSource {
        let products = ["TestPackage", "TestExecutable", "SkipMe"]
        for product in products {
            let sourcesURL = directory.appendingPathComponent("Sources")
            let productDirectory = sourcesURL.appendingPathComponent(product)
            try FileManager.default.createDirectory(at: productDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions : 0o777])
            let source = "print(\"Hello Test Package!\")"
            let sourceFileURL = productDirectory.appendingPathComponent("main.swift")
            try (source as NSString).write(to: sourceFileURL,
                                           atomically: true,
                                           encoding: String.Encoding.utf8.rawValue)
        }
    }
    return directoryPath
}
