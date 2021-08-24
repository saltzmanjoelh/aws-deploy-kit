//
//  Packager.swift
//  
//
//  Created by Joel Saltzman on 5/16/21.
//

import Foundation
import Logging
import LogKit

public protocol ProductPackager {
    func packageProduct(_ product: Product, at packageDirectory: URL, services: Servicable) throws -> URL
    func destinationURLForProduct(_ product: Product, in packageDirectory: URL) -> URL
    func createDestinationDirectory(_ destinationDirectory: URL, services: Servicable) throws
    func prepareDestinationDirectory(product: Product, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws
    func copyProduct(product: Product, at packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws
    func copyEnvFile(at packageDirectory: URL, product: Product, destinationDirectory: URL, services: Servicable) throws
    func copySwiftDependencies(for product: Product, at packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws
    func getLddDependencies(for product: Product, at packageDirectory: URL, services: Servicable) throws -> [URL]
    func copyDependency(_ dependency: URL, in packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws
    @discardableResult
    func addBootstrap(for product: Product, in destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs
    func archiveContents(for product: Product, in destinationDirectory: URL, services: Servicable) throws -> URL
    func archivePath(for product: Product, in destinationDirectory: URL) -> URL
    func URLForEnvFile(packageDirectory: URL, product: Product) -> URL
}


// MARK: - Packager
public struct Packager: ProductPackager {
    
    public init() {}
    
    /// After you have built a product in Docker, this will package it and it's library dependencies into a zip archive
    /// and store it in the `destinationDirectory`. The default for this directory is a custom `lambda` sub-directory
    /// of the Swift package's `.build` sub-directory. ie: `MyPackage/.build/lambda/product.zip`.
    /// - Parameters:
    ///   - product: The name of the product that you want to package into a zip archive.
    ///   - packagePath: A path to the Swift Package that contains the built product you are trying to package.
    /// - Returns URL to the zip archive which contain the built product, dependencies and "bootstrap" symlink
    /// - Throws: If one of the steps has an error.
    public func packageProduct(_ product: Product, at packageDirectory: URL, services: Servicable) throws -> URL {
        services.logger.trace("--- Packaging : \(product) ---")
        // We will be copying the built binary in the packageDirectory to the destination
        // The destination defaults to .build/lambda/$product/
        let destinationDirectory = destinationURLForProduct(product, in: packageDirectory)
        
        try services.packager.createDestinationDirectory(destinationDirectory, services: services)
        
        // Copy files to destination directory
        try services.packager.prepareDestinationDirectory(product: product,
                                                          packageDirectory: packageDirectory,
                                                          destinationDirectory: destinationDirectory,
                                                          services: services)
        
        // Zip everything up
        return try services.packager.archiveContents(for: product,
                                                     in: destinationDirectory,
                                                     services: services)
    }
    
    public func createDestinationDirectory(_ destinationDirectory: URL, services: Servicable) throws {
        // Make sure that there isn't a file there already
        try? services.fileManager.removeItem(at: destinationDirectory)
        
        // Create the destination directory if it doesn't already exist
        try services.fileManager.createDirectory(at: destinationDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: [:])
    }
    
    /// Copies the built product in the package directory to a destination directory.
    /// Along with the .env file if one exists, product dependencies and creates the
    /// bootstrap file.
    /// - Parameters:
    ///   - product: The name of the product to copy
    ///   - packageDirectory: The directory of the product's Swift Package
    ///   - destinationDirectory: The directory to copy the binary to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: If there was a problem copying the .env file to the destination.
    public func prepareDestinationDirectory(product: Product, packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        // Copy the product
        try services.packager.copyProduct(product: product,
                                             at: packageDirectory,
                                             destinationDirectory: destinationDirectory,
                                             services: services)
        
        guard product.type == .executable else { return }
        
        // If there is a .env file, copy it too
        try services.packager.copyEnvFile(at: packageDirectory,
                                          product: product,
                                          destinationDirectory: destinationDirectory,
                                          services: services)
        
        // Use ldd to copy the Swift dependencies
        try services.packager.copySwiftDependencies(for: product,
                                                    at: packageDirectory,
                                                    to: destinationDirectory,
                                                    services: services)
        
        // Symlink the product to "bootstrap"
        try services.packager.addBootstrap(for: product,
                                           in: destinationDirectory,
                                           services: services)
    }
    
    /// Copies the built product in the releases directory to a destination directory.
    /// - Parameters:
    ///   - product: The name of the product to copy
    ///   - packageDirectory: The directory of the product's Swift Package
    ///   - destinationDirectory: The directory to copy the binary to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: If there was a problem copying the .env file to the destination.
    public func copyProduct(product: Product, at packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        services.logger.trace("Copy Product: \(product)")
        let productFile = Builder.URLForBuiltProduct(product, at: packageDirectory, services: services)
        guard services.fileManager.fileExists(atPath: productFile.path) else {
            throw PackagerError.productNotFound(productFile.path)
        }
        
        let destinationFile = destinationDirectory.appendingPathComponent(product.name, isDirectory: false)
        try? services.fileManager.removeItem(at: destinationFile)
        try services.fileManager.copyItem(at: productFile, to: destinationFile)
    }
    
    /// Copies the .env file for an product in the package to a destination directory.
    /// - Parameters:
    ///   - packageDirectory: The directory of the Package
    ///   - product: The name of the product directory that contains the .env file
    ///   - destinationDirectory: The directory to copy the .env file to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: If there was a problem copying the .env file to the destination.
    public func copyEnvFile(at packageDirectory: URL, product: Product, destinationDirectory: URL, services: Servicable) throws {
        services.logger.trace("Copy .env: \(product)")
        let envFile = URLForEnvFile(packageDirectory: packageDirectory, product: product)
        
        // It's ok if the .env isn't there, just move on
        guard services.fileManager.fileExists(atPath: envFile.path) else { return }
        
        let destinationFile = destinationDirectory.appendingPathComponent(".env")
        try services.fileManager.copyItem(at: envFile, to: destinationFile)
    }
    
    /// Uses ldd within a Docker container to get a list of the product's dependencies.
    /// All of those dependencies are then copied to the destination directory.
    /// - Parameters:
    ///   - product: The name of the exectable that you want to copy the dependencies for.
    ///   - packageDirectory: An URL that points to the product's Package's directory
    ///   - destinationDirectory: The directory to copy the dependencies to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: if one of the steps fails.
    public func copySwiftDependencies(for product: Product, at packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        services.logger.trace("Copy Swift Dependencies: \(product)")
        // Use ldd to get a list of Swift dependencies
        let dependencies = try getLddDependencies(for: product, at: packageDirectory, services: services)
        // Iterate the URLs and copy the files
        try dependencies.forEach({
//            Should be a docker command to copy the files
            try copyDependency($0, in: packageDirectory, to: destinationDirectory, services: services)
        })
    }
    
    /// Uses ldd within a Docker container to get a list of the product's dependencies.
    /// - Parameters:
    ///   - product: The name of the exectable that you want to copy the dependencies for.
    ///   - packageDirectory: An URL that points to the product's Package's directory
    /// - Returns: An array of full path's to the dependencies.
    /// - Throws: if there is a problem getting the Swift dependencies.
    /// Output Example
    /// ```
    ///    linux-vdso.so.1 (0x00007fff84ba2000)
    ///    libswiftCore.so => /usr/lib/swift/linux/libswiftCore.so (0x00007fb41d09c000)
    /// ```
    public func getLddDependencies(for product: Product, at packageDirectory: URL, services: Servicable) throws -> [URL] {
        let lddCommand = "ldd .build/release/\(product)"
        let lines = try Docker.runShellCommand(lddCommand, at: packageDirectory, services: services)
            .allEntries
            .map({ (entry: LogCollector.Logs.Entry) -> String in // Get the raw message
                entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            .filter({ $0.contains("swift") }) // Filter only the lines that contain "swift"
            .map({ (output: String) -> [String] in
                output.components(separatedBy: "\n")
            })
            .flatMap({ $0 })
        return lines.compactMap { Self.parseLddLine($0)}
        // Prefix the packageDirectory and ".build/release/" to the names to get the full path
        .map({ URL(fileURLWithPath: $0) })
    }
    
    /// Parse the output of the ldd output.
    /// A line of output will look like this: `libswiftCore.so => /usr/lib/swift/linux/libswiftCore.so (0x00007fb41d09c000)`
    /// - Parameters:
    /// - line: A single line of ldd output in the form: `libswiftCore.so => /usr/lib/swift/linux/libswiftCore.so (0x00007fb41d09c000)`
    /// - Returns: The path to the dependency: `/usr/lib/swift/linux/libswiftCore.so`
    static func parseLddLine(_ line: String) -> String? {
        // Get the third column for each line
        // [0] == "libswiftCore.so", [1] == "=>", [2] == "/usr/lib/swift/linux/libswiftCore.so", [3] == "(0x00007fb41d09c000)"
        let components = line.components(separatedBy: " ")
        guard components.count == 4 else { return nil }
        return components[2]
    }
    
    /// Uses Docker to copy a dependency to the destination directory.
    public func copyDependency(_ dependency: URL, in packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        let logs = try Docker.runShellCommand("cp \(dependency.path) \(destinationDirectory.path)",
                                              at: packageDirectory,
                                              services: services)
        let errors = logs.filter(level: .error)
        if errors.count > 0 {
            let message = errors.map({ $0.message }).joined(separator: "\n")
            throw PackagerError.dependencyFailure(dependency, message)
        }
    }
    
    /// AWS Lambda requires a bootstrap file. It's simply a symlink to the product to run.
    /// - Parameters:
    ///   - product: The name of the exectable that you want to symlink
    ///   - packageDirectory: An URL that points to the product's Package's directory
    /// - Returns: An array of full path's to the dependencies.
    /// - Throws: if there is a problem creating the symlink
    @discardableResult
    public func addBootstrap(for product: Product, in destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        services.logger.trace("Adding bootstrap: \(product)")
        let command = "ln -s \(product) bootstrap"
        let logs: LogCollector.Logs = try services.shell.run(command, at: destinationDirectory, logger: services.logger)
        let errors = logs.allEntries.filter({ entry in
            return entry.level == .error
        })
        guard errors.count == 0 else {
            let messages = errors.compactMap({ $0.message }).joined(separator: "\n")
            throw PackagerError.bootstrapFailure(messages)
        }
        return logs
    }
    
    /// After we copy everything to the destinationDirectory, we need to zip it all up.
    /// - Parameters:
    ///  - product: The name of the product that we are packaging up.
    ///  - destinationDirectory: The directory that we copied the files to.
    /// - Returns: The URL of the zip that we packaged everything into
    public func archiveContents(for product: Product, in destinationDirectory: URL, services: Servicable) throws -> URL {
        // zip --symlinks $zipName * .env
        // echo -e "Built product at:\n$zipName"
        services.logger.trace("Archiving contents: \(product)")
        let archive = archivePath(for: product, in: destinationDirectory)
        let command = "zip --symlinks \(archive.path) * .env"
        let logs: LogCollector.Logs = try services.shell.run(command, at: destinationDirectory, logger: services.logger)
        let errors = logs.allEntries.filter({ entry in
            return entry.level == .error
        })
        guard errors.count == 0 else {
            let messages = errors.compactMap({ $0.message }).joined(separator: "\n")
            throw PackagerError.archivingFailure(messages)
        }
        guard services.fileManager.fileExists(atPath: archive.path) else {
            throw PackagerError.archiveNotFound(archive.path)
        }
        services.logger.trace("Archived \(product): \(archive)")
        return archive
    }
}


extension Packager {
    
    /// - Parameters
    ///   - product: The product target that we are packaging
    /// - Returns: URL destination for packaging everything before we zip it up
    public func destinationURLForProduct(_ product: Product, in packageDirectory: URL) -> URL {
        return packageDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent("lambda")
            .appendingPathComponent(product.name)
    }
    /// - Parameters
    ///   - packageDirectory:  The original directory of the package we are targeting
    ///   - product: The product target that we are packaging
    /// - Returns: URL destination for packaging everything before we zip it up
    public func URLForEnvFile(packageDirectory: URL, product: Product) -> URL {
        return URL(fileURLWithPath: packageDirectory
                    .appendingPathComponent("Sources")
                    .appendingPathComponent(product.name)
                    .appendingPathComponent(".env").path)
    }
    /// - Parameters
    ///   - product: The product target that we are packaging
    ///   - destinationDirectory: The directory that we are copying files to before zipping it up
    /// - Returns: URL destination for packaging everything before we zip it up
    public func archivePath(for product: Product, in destinationDirectory: URL) -> URL {
        return destinationDirectory
            .appendingPathComponent("\(product).zip")
    }
}
