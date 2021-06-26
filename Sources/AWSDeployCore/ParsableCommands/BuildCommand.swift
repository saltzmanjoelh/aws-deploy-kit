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

struct BuildCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "build",
                                                           abstract: "Build one or more executables inside of a Docker container. It will read your Swift package and build the executables of your choosing. If you leave the defaults, it will build all of the executables in the package. You can optionally choose to skip targets, or you can tell it to build only specific targets.\n\nThe Docker image `swift:5.3-amazonlinux2` will be used by default. You can override this by adding a Dockerfile to the root of the package's directory.\n\nThe built products will be available at `./build/lambda/$EXECUTABLE/`. You will also find a zip in there which contains everything needed to update AWS Lambda code. The archive will be in the format `$EXECUTABLE_NAME.zip`.\n")
    
    @OptionGroup
    var options: BuildOptions
}

struct BuildOptions: ParsableArguments {
    @OptionGroup
    var directory: DirectoryOption
    
    @Argument(help: "You can either specify which products you want to include, or if you don't specify any products, all will be used.")
    var products: [String] = []
    
    @Option(name: [.short, .long], help: "By default if you don't specify any products to build, all executable targets will be built. This allows you to skip specific products. Use a comma separted string. Example: -s SkipThis,SkipThat. If you specified one or more targets, this option is not applicable.")
    var skipProducts: String = ""
    
    @Option(name: [.customShort("e"), .long],
            help: "Run a custom shell command before the build phase. The command will be executed in the same source directory as the product(s) that you specify. If you don't specify any products and all products are built, then this command will be ran with each product in their source directory.")
    var preBuildCommand: String = ""
    
    @Option(name: [.customShort("o"), .long],
            help: "Run a custom shell command like \"aws sam-deploy\" after the build phase. The command will be executed in the same source directory as the product(s) that you specify. If you don't specify any products and all products are built, then this command will be ran after each product is built, in their source directory.")
    var postBuildCommand: String = ""
}

extension BuildCommand {
    public mutating func run() throws {
        Services.shared.builder.preBuildCommand = options.preBuildCommand
        Services.shared.builder.postBuildCommand = options.postBuildCommand
        _ = try self.run(services: Services.shared)
    }
    
    public mutating func run(services: Servicable) throws -> [URL] {
        try self.verifyConfiguration(services: services)
        let packageDirectory = URL(fileURLWithPath: options.directory.path)
        return try services.builder.buildProducts(options.products, at: packageDirectory, services: services)
    }
    
    /// Verifies the configuration and throws when it's invalid.
    /// Converts the default "./" into a fully expanded path.
    /// If no products were supplied, reads the package for a list of products.
    /// If any skip products were supplied, removes those.
    public mutating func verifyConfiguration(services: Servicable) throws {
        if self.options.directory.path == "./" ||
            self.options.directory.path == "."
        {
            self.options.directory.path = services.fileManager.currentDirectoryPath
        }
        services.logger.trace("Working in: \(self.options.directory.path)")
        
        if self.options.products.count == 0 {
            self.options.products = try self.getProducts(from: URL(fileURLWithPath: self.options.directory.path), of: .executable, services: services)
        }
        self.options.products = Self.removeSkippedProducts(self.options.skipProducts, from: self.options.products, logger: services.logger)
        if self.options.products.count == 0 {
            throw AppDeployerError.missingProducts
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
