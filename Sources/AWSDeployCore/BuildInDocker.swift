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

public struct BuildInDocker {
    
    public init() {}

    /// Build the products in Docker.
    /// - Returns: Array of URLs to the built archives. Their filenames will be in the format $executable-ISO8601Date.zip in UTC
    public func buildProducts(_ products: [String], at packageDirectory: URL, services: Servicable) throws -> [URL] {
        let dockerfilePath = try getDockerfilePath(from: packageDirectory, services: services)
        _ = try prepareDockerImage(at: dockerfilePath, services: services)
        let archiveURLs = try products.map { (product: String) -> URL in
            _ = try self.buildProduct(product, at: packageDirectory, services: services)
            let url = try self.getBuiltProductPath(at: packageDirectory, for: product, services: services)
            return url
        }
        return archiveURLs
    }

    
    /// Get the path of the Dockerfile in the target projects directory. If one isn't available a temporary one is provided.
    /// - Parameters:
    ///    - packagePath: A path to the Package's directory.
    /// - Returns:Path to the projects Dockerfile if it exists. Otherwise, the path to a temporary Dockerfile.
    func getDockerfilePath(from packageDirectory: URL, services: Servicable) throws -> URL {
        let dockerfile = packageDirectory.appendingPathComponent("Dockerfile")
        guard services.fileManager.fileExists(atPath: dockerfile.path)
        else {
            // Dockerfile was not available. Create a default Swift image to use for building with.
            return try createTemporyDockerfile(services: services)
        }
        return dockerfile
    }
    
    /// If a dockerfile was not provided, we create a temporary one to create a Swift Docker image from.
    /// - Returns: Path to the temporary Dockerfile
    func createTemporyDockerfile(services: Servicable) throws -> URL {
        services.logger.trace("Creating temporary Dockerfile")
        let dockerfile = URL(fileURLWithPath: "/tmp").appendingPathComponent("Dockerfile")
        try? services.fileManager.removeItem(at: dockerfile)
        // Create the Dockerfile
        let contents = "FROM \(Docker.Config.imageName)\nRUN yum -y install zip"
        try contents.write(to: dockerfile, atomically: true, encoding: .utf8)
        return dockerfile
    }

    /// Builds a new Docker image to build the products with.
    /// - Parameters:
    ///    - dockerfilePath: The directory where the Dockerfile is
    /// - Returns: The output from building the new image.
    public func prepareDockerImage(at dockerfilePath: URL, services: Servicable) throws -> String {
        services.logger.trace("Preparing Docker image.")
        guard services.fileManager.fileExists(atPath: dockerfilePath.path) else {
            throw BuildInDockerError.invalidDockerfilePath(dockerfilePath.path)
        }
        let directory = dockerfilePath.deletingLastPathComponent()
        let command = "/usr/local/bin/docker build --file \(dockerfilePath.path) . -t \(Docker.Config.containerName)  --no-cache"
        let output: String = try ShellExecutor.run(
            command,
            arguments: [],
            at: directory.path,
            logger: services.logger
        )
        return output
    }

    /// Build a Swift product in Docker
    /// - Parameters:
    ///   - product: The name of the product to build.
    ///   - packageDirectory: The directory to find the package in.
    /// - Returns: The output from building in Docker.
    public func buildProduct(_ product: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL? = nil) throws -> LogCollector.Logs {
        services.logger.trace("-- Building \(product) ---")
        let swiftBuildCommand = "swift build -c release --product \(product)"
        let logs: LogCollector.Logs
        do {
            logs = try Docker.runShellCommand(swiftBuildCommand, at: packageDirectory, logger: services.logger, sshPrivateKeyPath: sshPrivateKeyPath)
        } catch {
            if "\(error)".contains("root manifest not found") {
                services.logger.error("Did you specify a path to a Swift Package: \(packageDirectory)")
            }
            throw error
        }
        return logs
    }
    func getBuiltProductPath(at packageDirectory: URL, for product: String, services: Servicable) throws -> URL {
        let url = packageDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent("release")
            .appendingPathComponent(product)
        guard services.fileManager.fileExists(atPath: url.path) else {
            throw BuildInDockerError.builtProductNotFound(url.path)
        }
        return url
    }
}
