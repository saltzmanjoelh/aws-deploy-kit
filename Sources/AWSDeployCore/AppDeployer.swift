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

public enum ProductType: String {
    case library
    case executable
}

public enum AppDeployerError: Error, CustomStringConvertible {
    case missingProducts
    
    public var description: String {
        switch self {
        case .missingProducts:
            return "No executable products were found. Does the package description contain a products section with at least one executable type?"
        }
    }
}

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
        let archiveURLs = try services.builder.buildProducts(self.products, at: self.directoryPath, logger: services.logger)
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
            if self.skipProducts.count > 1 {
                services.logger.trace("Skipping: \(self.skipProducts)")
            }
            self.products = try self.getProducts(from: self.directoryPath, of: .executable, skipProducts: self.skipProducts, logger: services.logger)
        }
        print("COUNT: \(self.products.count) \(self.products)")
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
    ///   - skipProducts: The name of the products to exclude from the array.
    /// - Returns: Array of product names in the package.
    public func getProducts(from directoryPath: String, of type: ProductType = .executable, skipProducts: String = "", logger: Logger? = nil) throws -> [String] {
        let command = "swift package dump-package | sed -e 's|: null|: \"\"|g' | /usr/local/bin/jq '.products[] | (select(.type.\(type.rawValue))) | .name' | sed -e 's|\"||g'"
        let output = try ShellExecutor.run(
            command,
            at: directoryPath,
            outputHandle: FileHandle.standardOutput,
            errorHandle: FileHandle.standardError,
            logger: logger
        )
        // Remove empty values
        var allProducts: [String] = output
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "\n")
            .compactMap({
                let result = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                guard result.count > 0 else { return nil }
                return result
            })
        // Remove the products that were requested to be skipped
        let skips = skipProducts.components(separatedBy: ",")
        if skips.count > 0 {
            allProducts.removeAll { (product: String) -> Bool in
                skips.contains(product)
            }
        }
        guard allProducts.count > 0 else {
            throw AppDeployerError.missingProducts
        }
        return allProducts
    }
}
