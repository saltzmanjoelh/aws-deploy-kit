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
    
    public struct DockerConfig {
        public static let imageName = "swift:5.3-amazonlinux2"
        public static let containerName = "awsdeploykit-builder"
    }
    
    public init() {}

    /// Build the products in Docker.
    /// - Returns: Array of URLs to the built archives. Their filenames will be in the format $executable-yyyymmdd_HHMM.zip in UTC
    public func buildProducts(_ products: [String], at directoryPath: String, logger: Logger) throws -> [URL] {
        let dockerfilePath = try getDockerfilePath(from: directoryPath, logger: logger)
        _ = try prepareDockerImage(at: dockerfilePath, logger: logger)
        let archiveURLs = try products.map { (product: String) -> URL in
            let filePath = try buildAndPackageInDocker(product: product, at: directoryPath, logger: logger)
            guard let url = URL(string: filePath),
                  FileManager.default.fileExists(atPath: filePath)
            else {
                throw BuildInDockerError.archiveNotFound(filePath)
            }
            return url
        }
        return archiveURLs
    }

    
    /// Get the path of the Dockerfile in the target projects directory. If one isn't available a temporary one is provided.
    /// - Returns:Path to the projects Dockerfile if it exists. Otherwise, the path to a temporary Dockerfile.
    func getDockerfilePath(from directoryPath: String, logger: Logger) throws -> String {
        guard let dockerfile = URL(string: directoryPath)?.appendingPathComponent("Dockerfile"),
           FileManager.default.fileExists(atPath: dockerfile.absoluteString)
        else {
            // Dockerfile was not available. Create a default Swift image to use for building with.
            return try createTemporyDockerfile(logger: logger)
        }
        return dockerfile.path
    }
    
    /// If a dockerfile was not provided, we create a temporary one to create a Swift Docker image from.
    /// - Returns: Path to the temporary Dockerfile
    func createTemporyDockerfile(logger: Logger) throws -> String {
        logger.trace("Creating temporary Dockerfile")
        let dockerfile = URL(fileURLWithPath: "/tmp").appendingPathComponent("Dockerfile")
        try? FileManager.default.removeItem(at: dockerfile)
        // Create the Dockerfile
        let contents = "FROM \(BuildInDocker.DockerConfig.imageName)\nRUN yum -y install zip"
        try contents.write(to: dockerfile, atomically: true, encoding: .utf8)
        return dockerfile.absoluteString
    }

    /// Builds and archives the product in Docker.
    /// - Parameter product: The name of the product in the package to be built.
    /// - Returns: Path to the archive of the built product.
    public func buildAndPackageInDocker(product: String, at directoryPath: String, logger: Logger) throws -> String {
        _ = try self.buildProductInDocker(product, at: directoryPath, logger: logger)
        let archivePath = try packageProduct(product, at: directoryPath, logger: logger)
        return archivePath
    }

    /// Builds a new Docker image to build the products with.
    /// - Parameter dockerfilePath: The direcotry where the Dockerfile is
    /// - Returns: The output from building the new image.
    public func prepareDockerImage(at dockerfilePath: String, logger: Logger) throws -> String {
        logger.trace("Preparing Docker image.")
        guard let directory = URL(string: dockerfilePath)?.deletingLastPathComponent() else {
            throw BuildInDockerError.invalidDockerfilePath(dockerfilePath)
        }
        let command = "export PATH=$PATH:/usr/local/bin/ && /usr/local/bin/docker build --file \(dockerfilePath) . -t \(DockerConfig.containerName)  --no-cache"
        let output: String = try ShellExecutor.run(
            command,
            arguments: [],
            at: directory.path,
            logger: logger
        )
        return output
    }

    /// Build a Swift product in Docker
    /// - Parameters:
    ///   - product: The name of the product to build.
    ///   - directoryPath: The directory to find the package in.
    /// - Returns: The output from building in Docker.
    public func buildProductInDocker(_ product: String, at directoryPath: String, logger: Logger, sshPrivateKeyPath: String? = nil) throws -> String {
        logger.trace("-- Building \(product) ---")
        let command = "/usr/local/bin/docker"
        var arguments = [
            "run",
            "-i",
            "--rm",
            "-e",
            "TERM=dumb",
            "-e",
            "GIT_TERMINAL_PROMPT=1",
            "-v",
            "\(directoryPath):\(directoryPath)",
            "-w",
            directoryPath,
        ]
        let swiftBuildCommand = "swift build -c release --product \(product)"
        if let privateKeyPath = sshPrivateKeyPath {
            // We need the path to the key mounted and
            // need to use the ssh-agent command
            arguments += [
                "-v",
                "\(privateKeyPath):\(privateKeyPath)",
                DockerConfig.containerName,
                "ssh-agent",
                "bash",
                "-c",
                "ssh-add -c \(privateKeyPath); \(swiftBuildCommand)",
            ]
        } else {
            arguments += [
                DockerConfig.containerName,
                "/usr/bin/bash",
                "-c",
                "\"\(swiftBuildCommand)\"",
            ]
        }

        do {
            let output: String = try ShellExecutor.run(
                command,
                arguments: arguments,
                logger: logger
            )
            return output
        } catch {
            if "\(error)".contains("root manifest not found") {
                logger.error("Did you specify a path to a Swift Package: \(directoryPath)")
            }
            throw error
        }
    }

    /// Get the path to the script in the bundle
    /// - Parameter scriptName: Name of the script to get the path for
    /// - Throws: Throws if the script is not found.
    /// - Returns: Path to the script
    public func pathForBundleScript(_ scriptName: String) throws -> String {
        var result = scriptName
        if !result.contains("/") {
            // If it's not a path, it's just a script name and should be in the bundle
            if let bundlePath = Bundle.module.path(forResource: result, ofType: nil) {
                result = bundlePath
            } else {
                throw BuildInDockerError.scriptNotFound(result)
            }
        }
        return result
    }

    /// Run one of the provided shell scripts in Docker.
    /// - Parameters:
    ///   - script: Name of the script to run.
    ///   - arguments: Arguments to provide to the script.
    /// - Returns: Output from the script.
    public func runBundledScript(_ script: String, arguments: [String] = [], logger: Logger) throws -> String {
        let theScript = try pathForBundleScript(script)
        let parts: [String] = [theScript] + arguments
        logger.trace("\(parts.joined(separator: " "))")
        let output: String = try ShellExecutor.run(
            theScript,
            arguments: arguments,
            logger: logger
        )
        return output
    }

    /// Archive the product and Swift dependencies.
    /// - Parameters:
    ///   - product: The name of built product to archive.
    ///   - directoryPath: The directory where the built product is located.
    /// - Returns: Path to the new archive.
    public func packageProduct(_ product: String, at directoryPath: String, logger: Logger) throws -> String {
        let arguments = [directoryPath] + [product]
        logger.trace("-- Packaging \(product) ---")
        let output = try self.runBundledScript("packageInDocker.sh", arguments: arguments, logger: logger)
        guard let archivePath = output.components(separatedBy: "\n").last,
              archivePath.hasSuffix(".zip") // Last log should be the zip path
        else {
            throw BuildInDockerError.archivePathNotReceived(product)
        }
        // TODO: Check error logs and provide useful tips.
        return archivePath
    }
}
