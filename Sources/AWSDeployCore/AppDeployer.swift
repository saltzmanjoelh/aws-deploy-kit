//
//  AppDeployer.swift
//
//
//  Created by Joel Saltzman on 1/28/21.
//

import ArgumentParser
import Foundation
import Logging
import LogKit
import SotoLambda
import SotoS3

public struct AppDeployer: ParsableCommand {
    public static let configuration = CommandConfiguration(abstract: "Helps with building Swift packages in Linux and deploying to Lambda. Currently, we only support building executable targets.")

    @Option(name: [.short, .long], help: "Provide a custom path to the project directory instead of using the current working directory.")
    var directoryPath: String = "./"

    @Option(name: [.short, .long], help: "Skip specific products. Use a comma separted string. Example: -s SkipThis,SkipThat. This is only applicable if you didn't specify the products.")
    var skipProducts: String = ""

    @Argument(help: "You can either specify which products you want to include. Or if you don't specify any, all will be used. You can optionally skip some products using the --skip-products (-s) flag.")
    var products: [String] = []

    @Flag(name: [.short, .long], help: "Publish the updated Lambda functions with a blue green process. A new Lambda version will be created for an existing function that uses the same product name from the archive. Archives are created with the format 'PRODUCT_DATE.zip'. Next, the Lamdba will be invoked to make sure that it hasn't crashed on startup. Finally, the 'production' alias for the Lambda will be updated to point to the new revision.")
    var publishBlueGreen: Bool = false

    public init() {}

    public mutating func run() throws {
        try self.run(services: Services.shared)
    }

    public mutating func run(services: Servicable) throws {
        try self.verifyConfiguration(services: services)
        let archiveURLs = try services.builder.buildProducts(products, at: URL(fileURLWithPath: directoryPath), services: services)
        if self.publishBlueGreen == true {
            _ = try services.publisher.publishArchives(archiveURLs, services: services).wait()
        }
    }

    /// Verifies the configuration and throws when it's invalid.
    public mutating func verifyConfiguration(services: Servicable) throws {
        if self.directoryPath == "./" ||
            self.directoryPath == "."
        {
            self.directoryPath = FileManager.default.currentDirectoryPath
        }
        services.logger.trace("Working in: \(self.directoryPath)")

        if self.products.count == 0 {
            self.products = try self.getProducts(from: self.directoryPath, of: .executable, logger: services.logger)
        }
        self.products = Self.removeSkippedProducts(self.skipProducts, from: self.products, logger: services.logger)
        if self.products.count == 0 {
            throw AppDeployerError.missingProducts
        }
        if self.publishBlueGreen {
            services.logger.trace("Deploying: \(self.products)")
        }
    }

    /// Get an array of products of a specific type in a Swift package.
    /// - Parameters:
    ///   - directoryPath: String path to the directory that contains the package.
    ///   - type: The ProductTypes you want to get.
    /// - Returns: Array of product names in the package.
    public func getProducts(from directoryPath: String, of type: ProductType = .executable, logger: Logger? = nil) throws -> [String] {
        let command = "swift package dump-package"
        let logs: LogCollector.Logs = try ShellExecutor.run(
            command,
            at: directoryPath,
            logger: logger
        )

        // For some unknown reason, we get this error in stderr
        // Failed to open macho file at /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift for reading: Too many levels of symbolic links
        // Filter the logs so that we only read trace level messages and ignore that error that came from stderr
        guard let output = logs.filter(level: .trace).last?.message, // Get the last line of output, it should be json
            let data = output.data(using: .utf8) else {
            throw AppDeployerError.packageDumpFailure
        }
        let package = try JSONDecoder().decode(SwiftPackage.self, from: data)
        
        // Remove empty values
        let allProducts: [String] = package.products.filter { (product: SwiftPackage.Product) in
            product.isExecutable == (type == .executable)
        }.map({ $0.name })
        return allProducts
    }
    
    /// Filters the `skipProducts` from the list of `products`.
    /// If the running process named `processName` is in the list of products,
    /// it will be skipped as well. We do this for when we want to include a deployment target in a project.
    /// The deployment target deploys the executables in the package. However, the deployment target is
    /// an executable itself. We don't want to have to specify that it should skip itself. We know that it should
    /// be skipped.
    /// - Returns: An array of product names with the `skipProducts` and `processName` filtered out.
    static func removeSkippedProducts(_ skipProducts: String,
                                      from products: [String],
                                      logger: Logger,
                                      processName: String = ProcessInfo.processInfo.processName) -> [String] {
        var skips = skipProducts
            .components(separatedBy: ",")
            .filter({ $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 })
        var remainingProducts = products
        if remainingProducts.contains(processName) {
            skips.append(processName)
        }
        guard skips.count > 0 else { return remainingProducts }

        // Remove the products that were requested to be skipped
        logger.trace("Skipping: \(skips.joined(separator: ", "))")
        if skips.count > 0 {
            remainingProducts.removeAll { (product: String) -> Bool in
                skips.contains(product)
            }
        }
        return remainingProducts
    }
}
