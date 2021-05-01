//
//  AppDeployer.swift
//  
//
//  Created by Joel Saltzman on 1/28/21.
//

import Foundation
import ArgumentParser
import LogKit
import Logging
import SotoS3
import SotoLambda


//public enum AWSDeployError: Error, CustomStringConvertible {
//    case invalidBucket
//
//    public var description: String {
//        switch self {
//        case .invalidBucket:
//            return "Bucket name was empty. The -b option should be followed by the bucket name. ie: -b \"bucket-name\""
//        }
//    }
//}


public enum ProductType: String {
    case library = "library"
    case executable = "executable"
}


public struct AppDeployer: ParsableCommand {
    
    public static let configuration = CommandConfiguration(abstract: "Helps with building Swift packages in Linux and deploying to Lambda.")

    @Option(name: [.short, .long], help: "Provide a custom path to the project directory instead of using the current working directory.")
    var directoryPath: String = "./"
    
    @Option(name: [.short, .long], help: "Skip specific products. Use a comma separted string. Example: -s SkipThis,SkipThat. This is only applicable if you didn't specify the products.")
    var skipProducts: String = ""
    
    @Argument(help: "You can either specify which products you want to include. Or if you don't specify any, all will be used. You can optionally skip some products using the --skip-products (-s) flag.")
    var products: [String] = []
    
    @Flag(name: [.short, .long], help: "Publish the updated Lambda functions with a blue green process. A new Lambda version will be created for an existing function that uses the same product name from the archive. Archives are created with the format 'PRODUCT_DATE.zip'. Next, the Lamdba will be invoked to make sure that it hasn't crashed on startup. Finally, the 'production' alias for the Lambda will be updated to point to the new revision.")
    var publishBlueGreen: Bool = false
    
//    @Option(name: [.short, .long], help: "S3 bucket to deploy all of the archives to. Example: -b app-bucket")
//    var bucket: String?
//
//    @Option(name: [.short, .long], help: "AWS regions to use for actions like S3 upload. Example: -r us-west-1")
//    var region: String = "us-west-1"
    
    public init() {}
    
    public mutating func run() throws {
        try run(services: Services.shared)
    }
    public mutating func run(services: Servicable) throws {
        try verifyConfiguration(services: services)
        let archiveURLs = try services.builder.buildProducts(products, at: directoryPath, logger: services.logger)
//        if let bucketName = bucket {
//            _ = try services.uploader.uploadArchives(archiveURLs, bucket: bucketName, services: services).wait()
//        }
        if publishBlueGreen == true {
            _ = try services.publisher.publishArchives(archiveURLs, services: services).wait()
        }
    }
    
    
    /// Verifies the configuration and throws when it's invalid.
    public mutating func verifyConfiguration(services: Servicable) throws {
        if directoryPath == "./" ||
            directoryPath == "." {
            directoryPath = FileManager.default.currentDirectoryPath
        }
        services.logger.info("Working in: \(directoryPath)")

        if products.count == 0 {
            if skipProducts.count > 1 {
                services.logger.info("Skipping: \(skipProducts)")
            }
            products = try getProducts(from: directoryPath, of: .executable, skipProducts: skipProducts, logger: services.logger)
        }
//        if let s3Bucket = bucket {
//            if s3Bucket == "" {
//                throw AWSDeployError.invalidBucket
//            }
//            services.logger.info("Deploying: \(products) to bucket: \(s3Bucket)")
        if publishBlueGreen {
            services.logger.info("Deploying: \(products)")
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
        let output = try ShellExecutor.run(command,
                                           at: directoryPath,
                                           outputHandle: FileHandle.standardOutput,
                                           errorHandle: FileHandle.standardError,
                                           logger: logger)
        var allProducts = output.components(separatedBy: "\n")
        let skips = skipProducts.components(separatedBy: ",")
        if skips.count > 0 {
            allProducts.removeAll { (product: String) -> Bool in
                skips.contains(product)
            }
        }
        return allProducts
    }
}
