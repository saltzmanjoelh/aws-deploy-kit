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
    
    func parseProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [Product]
    func loadProducts(at packageDirectory: URL, services: Servicable) throws -> [Product]
    
    func buildProducts(_ products: [Product], at packageDirectory: URL, sshPrivateKeyPath: URL?, services: Servicable) throws -> [URL]
    func prepareDocker(packageDirectory: URL, services: Servicable) throws
    func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL
    func createTemporaryDockerfile(services: Servicable) throws -> URL
    func prepareDockerImage(at dockerfilePath: URL, services: Servicable) throws -> String
    func buildAndPackage(product: Product, at packageDirectory: URL, sshPrivateKeyPath: URL?, services: Servicable) throws -> URL
    func buildProduct(_ product: Product, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> URL
    func executeShellCommand(_ command: String, for product: Product, at packageDirectory: URL, services: Servicable) throws
    func buildProductInDocker(_ product: Product, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL?) throws -> LogCollector.Logs
    func getBuiltProductPath(product: Product, at packageDirectory: URL, services: Servicable) throws -> URL
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
    ///    - sshPrivateKeyPath: The private key to pull from private repos with.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns: Array of URLs to the archive that contains built the products and their dependencies.
    public func buildProducts(_ products: [Product], at packageDirectory: URL, sshPrivateKeyPath: URL? = nil, services: Servicable) throws -> [URL] {
        services.logger.trace("Build products at: \(packageDirectory.path)")
        try prepareDocker(packageDirectory: packageDirectory, services: services)
        let archiveURLs = try products.map { (product: Product) -> URL in
            try services.builder.buildAndPackage(product: product, at: packageDirectory, sshPrivateKeyPath: sshPrivateKeyPath, services: services)
        }
        return archiveURLs
    }
    
    
    /// Builds the product in Docker, then packages it with it's library dependencies into a zip.
    /// - Parameters:
    ///   - product: The product from a Swift package to build and archive.
    ///   - packageDirectory: The directory of the Swift package that the product is from.
    ///   - sshPrivateKeyPath: An ssh private key that can be used to pull Swift dependencies from private repos.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: An URL to a zip archive that contains the built product and it's library dependencies.
    public func buildAndPackage(product: Product, at packageDirectory: URL, sshPrivateKeyPath: URL?, services: Servicable) throws -> URL {
        _ = try services.builder.buildProduct(product,
                                              at: packageDirectory,
                                              services: services,
                                              sshPrivateKeyPath: sshPrivateKeyPath)
        return try services.packager.packageProduct(product, at: packageDirectory, services: services)
    }
    
    /// Builds the product in Docker.
    /// - Parameters:
    ///   - product: The product that you want to build.
    ///   - packageDirectory: The Swift package that the product is in.
    ///   - services: The set of services which will be used to execute your request with.
    ///   - sshPrivateKeyPath: The private key to pull from private repos with.
    /// - Throws: If there was a problem building the product.
    /// - Returns: Archive to the built product
    public func buildProduct(_ product: Product,
                             at packageDirectory: URL,
                             services: Servicable = Services.shared,
                             sshPrivateKeyPath: URL? = nil) throws -> URL {
        // We change the path here so that when we process the pre and post commands, we can use a relative paths
        // to files that might be in their directories
        let sourceDirectory = packageDirectory.appendingPathComponent("Sources").appendingPathComponent(product.name)
        FileManager.default.changeCurrentDirectoryPath(sourceDirectory.path)
        services.logger.trace("Build \(product) at: \(sourceDirectory.path)")
        try services.builder.executeShellCommand(preBuildCommand, for: product, at: sourceDirectory, services: services)
        _ = try services.builder.buildProductInDocker(product, at: packageDirectory, services: services, sshPrivateKeyPath: sshPrivateKeyPath)
        let url = try services.builder.getBuiltProductPath(product: product, at: packageDirectory, services: services)
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
    public func buildProductInDocker(_ product: Product, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL? = nil) throws -> LogCollector.Logs {
        services.logger.trace("-- Building \(product.name) ---")
        let flag = product.type == .executable "--product" ? "--target"
        let swiftBuildCommand = "swift build -c release \(flag) \(product.name)"
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
    ///   - product: The built product that should be in the release directory.
    ///   - product: The name of the
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: URL destination for packaging everything before we zip it up.
    static func URLForBuiltProduct(_ product: Product, at packageDirectory: URL, services: Servicable) -> URL {
        let dir = packageDirectory
                .appendingPathComponent(".build")
                .appendingPathComponent("release")
        if product.type == .executable {
            return dir.appendingPathComponent(product.name)
        }
        // Built libraries have some string substitution.
        // TODO: Check in the Swift compiler to see what else is replaced
        let productName = product.name.replacingOccurrences(of: "-", with: "_")
        return dir.appendingPathComponent("\(productName).swiftmodule") // Library
    }
    /// Get's the URL for the built product.
    /// - Parameters:
    ///   - product: The name of the product to build.
    ///   - packageDirectory: The directory to find the package in.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: URL of the built product.
    /// - Throws: If the built product is not available.
    public func getBuiltProductPath(product: Product, at packageDirectory: URL, services: Servicable) throws -> URL {
        let url = Self.URLForBuiltProduct(product,
                                          at: packageDirectory,
                                          services: services)
        guard services.fileManager.fileExists(atPath: url.path) else {
            throw DockerizedBuilderError.builtProductNotFound(url.path)
        }
        return url
    }
    
    /// Executes a shell command for a specific product in it's source directory.
    /// - Parameters:
    ///   - command: The shell command to execute.
    ///   - product: The product that you want to run the command for.
    ///   - packageDirectory: The Package's root directory.
    ///   - services: The set of services which will be used to execute your request with.
    public func executeShellCommand(_ command: String, for product: Product, at packageDirectory: URL, services: Servicable) throws {
        guard command.count > 0
        else { return }
        let targetDirectory = packageDirectory.appendingPathComponent("Sources").appendingPathComponent(product.name)
        let _: LogCollector.Logs = try services.shell.run(command, at: targetDirectory, logger: services.logger)
    }
}

// MARK: - Products
extension Builder {
    /// If no products were supplied, reads the package for a list of products. If any skip products were supplied, removes those.
    /// - Parameters:
    ///   - products: The products to validate. If you don't provide any, the `packageDirectory` will be parsed to get a list of products.
    ///   - skipProducts: The products that should be skipped
    ///   - packageDirectory: The Swift Package directory to check if no products are supplied.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Throws: Throws if it as problems getting the list of products from the package
    /// - Returns: The supplied products from either the input `products` or the `packageDirectory` minus the `skipProducs`.
    public func parseProducts(_ products: [String], skipProducts: String, at packageDirectory: URL, services: Servicable) throws -> [Product] {
        let allProducts = try services.builder.loadProducts(at: packageDirectory, services: services)
        var result: [Product] = products.count == 0 ? allProducts : allProducts.filter({ products.contains($0.name) })
        result = Self.removeSkippedProducts(skipProducts, from: result, logger: services.logger)
        if result.count == 0 {
            throw DockerizedBuilderError.missingProducts
        }
        return result
    }
    
    /// Get an array of products of a specific type in a Swift package.
    /// - Parameters:
    ///   - packageDirectory: String path to the directory that contains the package.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Throws: Throws if it as problems getting the list of products from the package
    /// - Returns: Array of product names in the package.
    public func loadProducts(at packageDirectory: URL, services: Servicable) throws -> [Product] {
        let command = "swift package dump-package"
        let logs: LogCollector.Logs = try services.shell.run(
            command,
            at: packageDirectory,
            logger: services.logger
        )
        
        // For some unknown reason, we get this error in stderr.
        // Failed to open macho file at /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift for reading: Too many levels of symbolic links.
        // Filter the logs so that we only read trace level messages and ignore that error that came from stderr.
        // It's all lines except the first error line
        let traces = logs.filter(level: .trace)
        let output = traces.compactMap({ $0.message }).joined(separator: "")
        guard let data = output.data(using: .utf8),
                data.count > 0
        else {
            throw DockerizedBuilderError.packageDumpFailure
        }
        let package = try JSONDecoder().decode(SwiftPackage.self, from: data)
        
        // Remove empty values
        let allProducts: [Product] = package.products.map({ Product(name: $0.name, type: $0.isExecutable ? .executable : .library ) })
        return allProducts
    }
    
    /// Filters the `skipProducts` from the list of `products`.
    /// If the running process named `processName` is in the list of products,
    /// it will be skipped as well. We do this for when we want to include a deployment target in a project.
    /// The deployment target deploys the products in the package. However, the deployment target is
    /// an executable itself. We don't want to have to specify that it should skip itself. We know that it should
    /// be skipped.
    /// - Parameters:
    ///   - skipProducts: The products to be removed from the supplied `products`
    ///   - products: The source products in the package.
    ///   - logger: The logger to log the result with.
    ///   - processName: The current running process. The default is provided. This is mostly here for testing.
    /// - Returns: An array of product names with the `skipProducts` and `processName` filtered out.
    static func removeSkippedProducts(_ skipProducts: String,
                                      from products: [Product],
                                      logger: Logger,
                                      processName: String = ProcessInfo.processInfo.processName) -> [Product] {
        var skips = skipProducts
            .components(separatedBy: ",")
            .filter({ $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 })
        var remainingProducts = products
        if remainingProducts.contains(where: { $0.name == processName }) {
            skips.append(processName)
        }
        guard skips.count > 0 else { return remainingProducts }
        
        // Remove the products that were requested to be skipped
        logger.trace("Skipping: \(skips.joined(separator: ", "))")
        if skips.count > 0 {
            remainingProducts.removeAll { (product: Product) -> Bool in
                skips.contains(product.name)
            }
        }
        return remainingProducts
    }
}

// MARK: - Docker
extension Builder {
    /// Using a Dockerfile either from the package directory or the default one,
    /// creates a new Docker image to build the products within.
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
}
