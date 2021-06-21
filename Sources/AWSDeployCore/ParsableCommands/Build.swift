//
//  File.swift
//  
//
//  Created by Joel Saltzman on 6/19/21.
//

import Foundation
import ArgumentParser
import Logging
import LogKit
import SotoLambda
import SotoS3

extension AWSDeploy {
    struct Build: ParsableCommand {
        public static let configuration = CommandConfiguration(abstract: "Build one or more executables inside of a Docker container. It will read your Swift package and build the executables of your choosing. If you leave the defaults, it will build all of the executables in the package. You can optionally choose to skip targets, or you can tell it to build only specific targets.\n\nThe Docker image `swift:5.3-amazonlinux2` will be used by default. You can override this by adding a Dockerfile to the root of the package's directory.\n\nThe built products will be available at `./build/lambda/$EXECUTABLE/`. You will also find a zip in there which contains everything needed to update AWS Lambda code. The archive will be in the format `$EXECUTABLE_NAME.zip`.\n")
        
        // Everything shares the -d, --directory-path option to specify the Swift package directory
        @OptionGroup
        var directory: DirectoryOption
        
        @Argument(help: "You can either specify which products you want to include, or if you don't specify any products, all will be used.")
        var products: [String] = []
        
        @Option(name: [.short, .long], help: "By default if you don't specify any products to build, all executable targets will be built. This allows you to skip specific products. Use a comma separted string. Example: -s SkipThis,SkipThat. If you specified one or more targets, this option is not applicable.")
        var skipProducts: String = ""

        @Flag(name: [.short, .customLong("publish")], help: "Publish to a Lambda function(s) with a blue green process. A new Lambda version will be created for an existing function that uses the same product name from the archive. Archives are created with the format '$EXECUTABLE_NAME.zip'. Next, the Lamdba will be invoked to make sure that it hasn't crashed on startup. Finally, the specified alias for the Lambda (the default is 'development') will be updated to point to the new revision. You can override the alias name with -a or --alias. Please see the publish help for reference.")
        var publish: Bool = false
        
        @OptionGroup
        var publishOptions: PublishOptions
        
        @Option(name: [.customShort("q"), .long],
                help: "Run a custom shell command before the build phase. The command will be executed in the same source directory as the product(s) that you specify. If you don't specify any products and all products are built, then this command will be ran with each product in their source directory.")
        var preBuildCommand: String = ""
        
        @Option(name: [.customShort("r"), .long],
                help: "Run a custom shell command like \"aws sam-deploy\" after the build phase. The command will be executed in the same source directory as the product(s) that you specify. If you don't specify any products and all products are built, then this command will be ran after each product is built, in their source directory.")
        var postBuildCommand: String = ""
    }
}

extension AWSDeploy.Build {
    public mutating func run() throws {
        Services.shared.publisher.functionRole = publishOptions.functionRole
        Services.shared.publisher.alias = publishOptions.alias
        Services.shared.builder.preBuildCommand = preBuildCommand
        Services.shared.builder.postBuildCommand = postBuildCommand
        try self.run(services: Services.shared)
    }

    public mutating func run(services: Servicable) throws {
        try self.verifyConfiguration(services: services)
        let packageDirectory = URL(fileURLWithPath: directory.path)
        let archiveURLs = try services.builder.buildProducts(products, at: packageDirectory, services: services)
            .map({ executableURL in
                try services.packager.packageExecutable(executableURL.lastPathComponent, at: packageDirectory, services: services)
            })
        if self.publish == true {
            _ = try services.publisher.publishArchives(archiveURLs, services: services).wait()
        }
        
    }

    /// Verifies the configuration and throws when it's invalid.
    public mutating func verifyConfiguration(services: Servicable) throws {
        if self.directory.path == "./" ||
            self.directory.path == "."
        {
            self.directory.path = services.fileManager.currentDirectoryPath
        }
        services.logger.trace("Working in: \(self.directory.path)")

        if self.products.count == 0 {
            self.products = try self.getProducts(from: URL(fileURLWithPath: self.directory.path), of: .executable, services: services)
        }
        self.products = Self.removeSkippedProducts(self.skipProducts, from: self.products, logger: services.logger)
        if self.products.count == 0 {
            throw AppDeployerError.missingProducts
        }
        if self.publish {
            services.logger.trace("Deploying: \(self.products)")
        }
    }

    /// Get an array of products of a specific type in a Swift package.
    /// - Parameters:
    ///   - directoryPath: String path to the directory that contains the package.
    ///   - type: The ProductTypes you want to get.
    /// - Returns: Array of product names in the package.
    public func getProducts(from directoryPath: URL, of type: ProductType = .executable, services: Servicable) throws -> [String] {
        let command = "swift package dump-package"
        let logs: LogCollector.Logs = try services.shell.run(
            command,
            at: directoryPath,
            logger: services.logger
        )

        // For some unknown reason, we get this error in stderr.
        // Failed to open macho file at /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift for reading: Too many levels of symbolic links.
        // Filter the logs so that we only read trace level messages and ignore that error that came from stderr.
        guard let output = logs.filter(level: .trace).last?.message, // Get the last line of output, it should be json.
            let data = output.data(using: .utf8),
            data.count > 0
        else {
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
