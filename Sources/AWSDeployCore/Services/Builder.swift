//
//  Builder.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import Logging
import LogKit
import NIO
import SotoS3

public protocol DockerizedBuilder {
    
    var preBuildCommand: String { get set }
    var postBuildCommand: String { get set }
    
    func parseProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [String]
    func getProducts(at packageDirectory: URL, type: ProductType, services: Servicable) throws -> [String]
    
    func buildProducts(_ products: [String], at packageDirectory: URL, skipProducts: String, sshPrivateKeyPath: URL?, services: Servicable) throws -> [URL]
    func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL
    func createTemporaryDockerfile(services: Servicable) throws -> URL
    func buildProduct(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> URL
    func prepareDockerImage(at dockerfilePath: URL, services: Servicable) throws -> String
    func executeShellCommand(_ command: String, for product: String, at packageDirectory: URL, services: Servicable) throws
    func buildProductInDocker(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs
    func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL
}


// MARK: - Builder
public struct Builder: DockerizedBuilder {
    
    public var preBuildCommand: String = ""
    public var postBuildCommand: String = ""
    
    public init() {}

    /// Build the products in Docker.
    /// - Parameters:
    ///    - products: Array of products in a package that you want to build.
    ///    - packageDirectory: The URL to the package that you want to build.
    ///    - skipProducts: The products to be removed from the supplied `products`.
    ///    - sshPrivateKeyPath: The private key to pull from private repos with.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns: Array of URLs to the archive that contains built executables and their dependencies.
    public func buildProducts(_ products: [String], at packageDirectory: URL, skipProducts: String = "", sshPrivateKeyPath: URL? = nil, services: Servicable) throws -> [URL] {
        services.logger.trace("Build products at: \(packageDirectory.path)")
        let parsedProducts = try parseProducts(products, skipProducts: skipProducts, at: packageDirectory, services: services)
        try prepareDocker(packageDirectory: packageDirectory, services: services)
        let archiveURLs = try parsedProducts.map { (product: String) -> URL in
            let executableURL = try services.builder.buildProduct(product,
                                                                  at: packageDirectory,
                                                                  services: services,
                                                                  sshPrivateKeyPath: sshPrivateKeyPath)
            return try services.packager.packageExecutable(executableURL.lastPathComponent, at: packageDirectory, services: services)
        }
        return archiveURLs
    }
    
    /// Using a Dockerfile either from the package directory or the default one,
    /// creates a new Docker image to build the executables within.
    /// - Parameters;
    ///    - packageDirectory: The Swift package directory that might contain the Dockerfile
    ///    - services: The set of services which will be used to execute your request with.
    public func prepareDocker(packageDirectory: URL, services: Servicable) throws {
        let dockerfilePath = try services.builder.getDockerfilePath(from: packageDirectory, services: services)
        _ = try services.builder.prepareDockerImage(at: dockerfilePath, services: services)
    }

    
    /// Get the path of the Dockerfile in the target projects directory. If one isn't available a temporary one is provided.
    /// - Parameters:
    ///   - packagePath: A path to the Package's directory.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns:Path to the projects Dockerfile if it exists. Otherwise, the path to a temporary Dockerfile.
    public func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL {
        let dockerfile = packageDirectory.appendingPathComponent("Dockerfile")
        guard services.fileManager.fileExists(atPath: dockerfile.path)
        else {
            // Dockerfile was not available. Create a default Swift image to use for building with.
            return try createTemporaryDockerfile(services: services)
        }
        return dockerfile
    }
    
    /// If a dockerfile was not provided, we create a temporary one to create a Swift Docker image from.
    /// - Parameter services: The set of services which will be used to execute your request with.
    /// - Throws: If there was a problem creating the directory.
    /// - Returns: Path to the temporary Dockerfile.
    public func createTemporaryDockerfile(services: Servicable) throws -> URL {
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
    ///   - dockerfilePath: The directory where the Dockerfile is.
    ///   - services: The set of services which will be used to execute your request with.
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
    ///   - command: The shell command to execute.
    ///   - product: The product that you want to run the command for.
    ///   - packageDirectory: The Package's root directory.
    ///   - services: The set of services which will be used to execute your request with.
    public func executeShellCommand(_ command: String, for product: String, at packageDirectory: URL, services: Servicable) throws {
        guard command.count > 0
        else { return }
        let targetDirectory = packageDirectory.appendingPathComponent("Sources").appendingPathComponent(product)
        let _: LogCollector.Logs = try services.shell.run(command, at: targetDirectory, logger: services.logger)
    }
    
    /// Builds the product in Docker.
    /// - Parameters:
    ///   - product: The executable that you want to build.
    ///   - packageDirectory: The Swift package that the executable is in.
    ///   - services: The set of services which will be used to execute your request with.
    ///   - sshPrivateKeyPath: The private key to pull from private repos with.
    /// - Throws: If there was a problem building the product.
    /// - Returns: Archive to the built product
    public func buildProduct(_ product: String,
                             at packageDirectory: URL,
                             services: Servicable = Services.shared,
                             sshPrivateKeyPath: URL? = nil) throws -> URL {
        // We change the path here so that when we process the pre and post commands, we can use a relative paths
        // to files that might be in their directories
        let sourceDirectory = packageDirectory.appendingPathComponent("Sources").appendingPathComponent(product)
        FileManager.default.changeCurrentDirectoryPath(sourceDirectory.path)
        services.logger.trace("Build \(product) at: \(sourceDirectory.path)")
        try services.builder.executeShellCommand(preBuildCommand, for: product, at: sourceDirectory, services: services)
        _ = try services.builder.buildProductInDocker(product, at: packageDirectory, services: services, sshPrivateKeyPath: nil)
        let url = try services.builder.getBuiltProductPath(at: packageDirectory, for: product, services: services)
        try services.builder.executeShellCommand(postBuildCommand, for: product, at: sourceDirectory, services: services)
        services.logger.trace("-- Built \(product) at: \(url) ---")
        return url
    }
    
    /// Build a Swift product in Docker.
    /// - Parameters:
    ///   - product: The name of the product to build.
    ///   - packageDirectory: The directory to find the package in.
    ///   - services: The set of services which will be used to execute your request with.
    ///   - sshPrivateKeyPath: A path to a private key if the dependencies are in a private repo
    /// - Returns: The output from building in Docker.
    public func buildProductInDocker(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL? = nil) throws -> LogCollector.Logs {
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
    ///   - product: The name of the
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: URL destination for packaging everything before we zip it up.
    static func URLForBuiltExecutable(_ executable: String, at packageDirectory: URL, services: Servicable) -> URL {
        return packageDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent("release")
            .appendingPathComponent(executable)
    }
    /// Get's the URL for the built product.
    /// - Parameters:
    ///   - packageDirectory: The directory to find the package in.
    ///   - product: The name of the product to build.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: URL of the built product.
    /// - Throws: If the built product is not available.
    public func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL {
        let url = Self.URLForBuiltExecutable(product,
                                             at: packageDirectory,
                                             services: services)
        guard services.fileManager.fileExists(atPath: url.path) else {
            throw DockerizedBuilderError.builtProductNotFound(url.path)
        }
        return url
    }
}

extension Builder {
    /// If no products were supplied, reads the package for a list of products. If any skip products were supplied, removes those.
    /// - Parameters:
    ///   - products: The products to validate. If you don't provide any, the `packageDirectory` will be parsed to get a list of executable products.
    ///   - skipProducts: The products that should be skipped
    ///   - packageDirectory: The Swift Package directory to check if no products are supplied.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Throws: Throws if it as problems getting the list of products from the package
    /// - Returns: The supplied products from either the input `products` or the `packageDirectory` minus the `skipProducs`.
    public func parseProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [String] {
        var result = products
        if products.count == 0 {
            result = try self.getProducts(at: packageDirectory, type: .executable, services: services)
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
    ///   - services: The set of services which will be used to execute your request with.
    /// - Throws: Throws if it as problems getting the list of products from the package
    /// - Returns: Array of product names in the package.
    public func getProducts(at packageDirectory: URL, type: ProductType = .executable, services: Servicable) throws -> [String] {
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
    /// - Parameters:
    ///   - skipProducts: The products to be removed from the supplied `products`
    ///   - products: The source products in the package.
    ///   - logger: The logger to log the result with.
    ///   - processName: The current running process. The default is provided. This is mostly here for testing.
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
