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

public enum BuildInDockerError: Error, CustomStringConvertible {
    case scriptNotFound(String)
    case archivePathNotReceived(String)
    case invalidArchivePath(String)

    public var description: String {
        switch self {
        case .scriptNotFound(let scriptName):
            return "The \(scriptName) script was not found in the resources."
        case .archivePathNotReceived(let productName):
            return "The path to the completed archive was not found for \(productName)."
        case .invalidArchivePath(let path):
            return "Invalid archive path: \(path)"
        }
    }
}

public struct BuildInDocker {
    public init() {}

    /// Build the products in Docker.
    /// - Returns: Array of URLs to the built archives. Their filenames will be in the format $executable-yyyymmdd_HHMM.zip in UTC
    public func buildProducts(_ products: [String], at directoryPath: String, logger: Logger) throws -> [URL] {
        if let dockerfile = URL(string: directoryPath)?.appendingPathComponent("Dockerfile"),
           FileManager.default.fileExists(atPath: dockerfile.absoluteString)
        {
            _ = try self.prepareDockerImage(at: directoryPath, logger: logger)
        }
        let archiveURLs = try products.map { (product: String) -> URL in
            let filePath = try buildAndPackageInDocker(product: product, at: directoryPath, logger: logger)
            guard let url = URL(string: filePath),
                  FileManager.default.fileExists(atPath: filePath)
            else {
                throw BuildInDockerError.invalidArchivePath(filePath)
            }
            return url
        }
        return archiveURLs
    }

    /// Builds and archives the product in Docker.
    /// - Parameter product: The name of the product in the package to be built.
    /// - Returns: Path to the archive of the built product.
    public func buildAndPackageInDocker(product: String, at directoryPath: String, logger: Logger) throws -> String {
        _ = try self.buildProductInDocker(product, at: directoryPath, logger: logger)
        guard let archivePath = try packageProduct(product, at: directoryPath, logger: logger),
              archivePath.hasSuffix(".zip")
        else { // Last log should be the zip path
            throw BuildInDockerError.archivePathNotReceived(product)
        }
        return archivePath
    }

    /// Builds a new Docker image to build the products with.
    /// - Parameter directoryPath: The direcotry where the Dockerfile is
    /// - Returns: The output from building the new image.
    public func prepareDockerImage(at directoryPath: String, logger: Logger) throws -> String {
        logger.trace("Preparing Docker image.")
        let command = "/bin/bash -c \"export PATH=$PATH:/usr/local/bin/ && /usr/local/bin/docker build . -t builder  --no-cache\"" // --build-arg WORKSPACE=\"$PWD\"
        logger.trace("\(command)")
        let output = try ShellExecutor.run(
            command,
            at: directoryPath,
            outputHandle: FileHandle.standardOutput,
            errorHandle: FileHandle.standardError,
            logger: logger
        )
        logger.trace("\(output)")
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
            "-it",
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
                "builder",
                "ssh-agent",
                "bash",
                "-c",
                "ssh-add -c \(privateKeyPath); \(swiftBuildCommand)",
            ]
        } else {
            arguments += [
                "builder",
                "/usr/bin/bash",
                "-c",
                "\"\(swiftBuildCommand)\"",
            ]
        }

        let output = try ShellExecutor.run(
            command,
            arguments: arguments,
            outputHandle: FileHandle.standardOutput,
            errorHandle: FileHandle.standardError,
            logger: logger
        )
        logger.trace("\(output)")
        return output
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
        let output = try ShellExecutor.run(
            theScript,
            arguments: arguments,
            outputHandle: FileHandle.standardOutput,
            errorHandle: FileHandle.standardError,
            logger: logger
        )
        logger.trace("\(output)")
        return output
    }

    /// Archive the product and Swift dependencies.
    /// - Parameters:
    ///   - product: The name of built product to archive.
    ///   - directoryPath: The directory where the built product is located.
    /// - Returns: Path to the new archive.
    public func packageProduct(_ product: String, at directoryPath: String, logger: Logger) throws -> String? {
        let arguments = [directoryPath] + [product]
        logger.trace("-- Packaging \(product) ---")
        return try self.runBundledScript("packageInDocker.sh", arguments: arguments, logger: logger).components(separatedBy: "\n").last
        // TODO: Check error logs and provide useful tips.
        // Maybe no rootManifest error means you didn't specify the source code directory
    }
}
