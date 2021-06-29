//
//  BuildInDocker.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import Logging
import LogKit
import NIO
import SotoS3

public protocol Builder {
    
    var preBuildCommand: String { get set }
    var postBuildCommand: String { get set }
    
    func buildProducts(_ products: [String], at packageDirectory: URL, skipProducts: String, services: Servicable) throws -> [URL]
    func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL
    func prepareDockerImage(at dockerfilePath: URL, services: Servicable) throws -> String
    func executeShellCommand(_ command: String, for product: String, at packageDirectory: URL, services: Servicable) throws
    func buildProduct(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs
    func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL
}

public struct DockerizedBuilder: Builder {
    
    public var preBuildCommand: String = ""
    public var postBuildCommand: String = ""
    
    public init() {}

    /// Build the products in Docker.
    /// - Returns: Array of URLs to the archive that contains built executables and their dependencies.
    public func buildProducts(_ products: [String], at packageDirectory: URL, skipProducts: String = "", services: Servicable) throws -> [URL] {
        services.logger.trace("Build products at: \(packageDirectory.path)")
        let parseProducts = try validateProducts(products, skipProducts: skipProducts, at: packageDirectory, services: services)
        let dockerfilePath = try services.builder.getDockerfilePath(from: packageDirectory, services: services)
        _ = try services.builder.prepareDockerImage(at: dockerfilePath, services: services)
        let executableURLs = try parseProducts.map { (product: String) -> URL in
            try services.builder.executeShellCommand(preBuildCommand, for: product, at: packageDirectory, services: services)
            _ = try services.builder.buildProduct(product, at: packageDirectory, services: services, sshPrivateKeyPath: nil)
            let url = try services.builder.getBuiltProductPath(at: packageDirectory, for: product, services: services)
            try services.builder.executeShellCommand(postBuildCommand, for: product, at: packageDirectory, services: services)
            services.logger.trace("-- Built \(product) at: \(url) ---")
            return url
        }
        return try executableURLs
            .map({ executableURL in
                try services.packager.packageExecutable(executableURL.lastPathComponent, at: packageDirectory, services: services)
            })
    }

    
    /// Get the path of the Dockerfile in the target projects directory. If one isn't available a temporary one is provided.
    /// - Parameters:
    ///    - packagePath: A path to the Package's directory.
    /// - Returns:Path to the projects Dockerfile if it exists. Otherwise, the path to a temporary Dockerfile.
    public func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL {
        let dockerfile = packageDirectory.appendingPathComponent("Dockerfile")
        guard services.fileManager.fileExists(atPath: dockerfile.path)
        else {
            // Dockerfile was not available. Create a default Swift image to use for building with.
            return try createTemporyDockerfile(services: services)
        }
        return dockerfile
    }
    
    /// If a dockerfile was not provided, we create a temporary one to create a Swift Docker image from.
    /// - Returns: Path to the temporary Dockerfile.
    func createTemporyDockerfile(services: Servicable) throws -> URL {
        let directoryURL = URL(fileURLWithPath: "/tmp/aws-deploy/")
        let dockerfile = directoryURL.appendingPathComponent("Dockerfile")
        services.logger.trace("Creating temporary Dockerfile in: \(directoryURL)")
        try? services.fileManager.removeItem(at: directoryURL)
        try services.fileManager.createDirectory(at: directoryURL,
                                                 withIntermediateDirectories: false,
                                                 attributes: nil)
        // Create the Dockerfile
        FileManager.default.changeCurrentDirectoryPath(directoryURL.path)
        let contents = "FROM \(Docker.Config.imageName)\nRUN yum install -y zip"
        try contents.write(toFile: dockerfile.lastPathComponent, atomically: true, encoding: .utf8)
        return dockerfile
    }

    /// Builds a new Docker image to build the products with.
    /// - Parameters:
    ///    - dockerfilePath: The directory where the Dockerfile is.
    /// - Returns: The output from building the new image.
    public func prepareDockerImage(at dockerfilePath: URL, services: Servicable) throws -> String {
        services.logger.trace("Preparing Docker image.")
        guard services.fileManager.fileExists(atPath: dockerfilePath.path) else {
            throw DockerizedBuilderError.invalidDockerfilePath(dockerfilePath.path)
        }
        let directory = dockerfilePath.deletingLastPathComponent()
        let command = "/usr/local/bin/docker build --file \(dockerfilePath.path) . -t \(Docker.Config.containerName)  --no-cache"
        let output: String = try services.shell.run(
            command,
            at: directory,
            logger: services.logger
        )
        return output
    }
    /// Executes a shell command for a specific product in it's source directory.
    /// - Parameters:
    /// - product: The product that you want to run the command for.
    /// - packageDirectory: The Package's root directory.
    public func executeShellCommand(_ command: String, for product: String, at packageDirectory: URL, services: Servicable) throws {
        guard command.count > 0
        else { return }
        let targetDirectory = packageDirectory.appendingPathComponent("Sources").appendingPathComponent(product)
        let _: LogCollector.Logs = try services.shell.run(command, at: targetDirectory, logger: services.logger)
    }

    /// Build a Swift product in Docker.
    /// - Parameters:
    ///   - product: The name of the product to build.
    ///   - packageDirectory: The directory to find the package in.
    /// - Returns: The output from building in Docker.
    public func buildProduct(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL? = nil) throws -> LogCollector.Logs {
        services.logger.trace("-- Building \(product) ---")
        let swiftBuildCommand = "swift build -c release --product \(product)"
        let logs: LogCollector.Logs
        do {
            logs = try Docker.runShellCommand(swiftBuildCommand, at: packageDirectory, services: services, sshPrivateKeyPath: sshPrivateKeyPath)
        } catch let error {
            if "\(error)".contains("root manifest not found") {
                services.logger.error("Did you specify a path to a Swift Package: \(packageDirectory)")
            }
            throw error
        }
        return logs
    }
    
    /// - Parameters
    ///   - executable: The built executable target that should be in the release directory.
    /// - Returns: URL destination for packaging everything before we zip it up.
    static func URLForBuiltExecutable(at packageDirectory: URL, for product: String, services: Servicable) -> URL {
        return packageDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent("release")
            .appendingPathComponent(product)
    }
    /// Get's the URL for the built product.
    /// - Parameters:
    ///   - packageDirectory: The directory to find the package in.
    ///   - product: The name of the product to build.
    /// - Returns: URL of the built product.
    /// - Throws: If the built product is not available.
    public func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL {
        let url = Self.URLForBuiltExecutable(at: packageDirectory,
                                             for: product,
                                             services: services)
        guard services.fileManager.fileExists(atPath: url.path) else {
            throw DockerizedBuilderError.builtProductNotFound(url.path)
        }
        return url
    }
}

extension DockerizedBuilder {
    /// If no products were supplied, reads the package for a list of products. If any skip products were supplied, removes those.
    public func validateProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [String] {
        var result = products
        if products.count == 0 {
            result = try self.getProducts(at: packageDirectory, of: .executable, services: services)
        }
        result = Self.removeSkippedProducts(skipProducts, from: result, logger: services.logger)
        if result.count == 0 {
            throw DockerizedBuilderError.missingProducts
        }
        return result
    }
    
    /// Get an array of products of a specific type in a Swift package.
    /// - Parameters:
    ///   - packageDirectory: String path to the directory that contains the package.
    ///   - type: The ProductTypes you want to get.
    /// - Returns: Array of product names in the package.
    public func getProducts(at packageDirectory: URL, of type: ProductType = .executable, services: Servicable) throws -> [String] {
        let command = "swift package dump-package"
        let logs: LogCollector.Logs = try services.shell.run(
            command,
            at: packageDirectory,
            logger: services.logger
        )
        
        // For some unknown reason, we get this error in stderr.
        // Failed to open macho file at /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift for reading: Too many levels of symbolic links.
        // Filter the logs so that we only read trace level messages and ignore that error that came from stderr.
        guard let output = logs.filter(level: .trace).last?.message, // Get the last line of output, it should be json.
              let data = output.data(using: .utf8),
              data.count > 0
        else {
            throw DockerizedBuilderError.packageDumpFailure
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
