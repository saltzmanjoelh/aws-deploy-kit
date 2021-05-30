//
//  PackageInDocker.swift
//  
//
//  Created by Joel Saltzman on 5/16/21.
//

import Foundation
import Logging
import LogKit

public struct PackageInDocker {
    
    let dateFormatter: ISO8601DateFormatter = {
        let result = ISO8601DateFormatter()
        return result
    }()
    public init() {}
    
    /// The sub-directory to copy packaged results to
    static var destinationDirectory = URL(fileURLWithPath: ".build").appendingPathComponent("lambda")
    
    /// After you have built an executable in Docker, this will package it and it's library dependencies into a zip archive
    /// and store it in the `destinationDirectory`. The default for this directory is a custom `lambda` sub-directory
    /// of the Swift package's `.build` sub-directory. ie: `MyPackage/.build/lambda/executable_datetimestamp_.zip`.
    /// - Parameters:
    ///   - executable: The name of the executable that you want to package into a zip archive.
    ///   - packagePath: A path to the Swift Package that contains the built executable you are trying to package.
    /// - Returns URL to the zip archive which contain the built executable, dependencies and "bootstrap" symlink
    /// - Throws: If one of the steps has an error.
    public func packageExecutable(_ executable: String, at packageDirectory: URL, services: Servicable) throws -> URL {
        services.logger.trace("Package Executable: \(executable)")
        // We will be copying the built binary in the packageDirectory to the destination
        // The destination defaults to .build/lambda/$executable/
        let destinationDirectory = destinationURLForExecutable(executable)
        
        // Make sure that there isn't a file there already
        try? services.fileManager.removeItem(at: destinationDirectory)
        
        // Create the destination directory if it doesn't already exist
        try services.fileManager.createDirectory(at: destinationDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        // Copy the executable
        try copyExecutable(executable: executable,
                           at: packageDirectory,
                           destinationDirectory: destinationDirectory,
                           services: services)
        
        // If there is a .env file, copy it too
        try copyEnvFile(at: packageDirectory,
                        executable: executable,
                        destinationDirectory: destinationDirectory,
                        services: services)
        
        // Use ldd to copy the Swift dependencies
        try copySwiftDependencies(for: executable,
                                  at: packageDirectory,
                                  to: destinationDirectory,
                                  services: services)
        
        // Symlink the executable to "bootstrap"
        try addBootstrap(for: executable,
                         in: destinationDirectory,
                         services: services)
        
        // Zip everything up
        return try archiveContents(for: executable,
                                   in: destinationDirectory,
                                   services: services)
    }
    
    /// Copies the built executable in the package directory to a destination directory.
    /// - Parameters:
    ///   - executable: The name of the executable to copy
    ///   - packageDirectory: The directory of the executable's Swift Package
    ///   - destinationDirectory: The directory to copy the binary to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: If there was a problem copying the .env file to the destination.
    func copyExecutable(executable: String, at packageDirectory: URL, destinationDirectory: URL, services: Servicable) throws {
        services.logger.trace("Copy Executable: \(executable)")
        let executableFile = URLForBuiltExecutable(executable)
        guard services.fileManager.fileExists(atPath: executableFile.path) else {
            throw PackageInDockerError.executableNotFound(executableFile.path)
        }
        
        let destinationFile = URL(fileURLWithPath: destinationDirectory.appendingPathComponent(executable).path)
        try? services.fileManager.removeItem(at: destinationFile)
        try services.fileManager.copyItem(at: executableFile, to: destinationFile)
    }
    
    /// Copies the .env file for an executable in the package to a destination directory.
    /// - Parameters:
    ///   - packageDirectory: The directory of the Package
    ///   - executable: The name of the executable directory that contains the .env file
    ///   - destinationDirectory: The directory to copy the .env file to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: If there was a problem copying the .env file to the destination.
    func copyEnvFile(at packageDirectory: URL, executable: String, destinationDirectory: URL, services: Servicable) throws {
        services.logger.trace("Copy .env: \(executable)")
        let envFile = URLForEnvFile(packageDirectory: packageDirectory, executable: executable)
        
        // It's ok if the .env isn't there, just move on
        guard services.fileManager.fileExists(atPath: envFile.path) else { return }
        
        let destinationFile = destinationDirectory.appendingPathComponent(".env")
        try services.fileManager.copyItem(at: envFile, to: destinationFile)
    }
    
    /// Uses ldd within a Docker container to get a list of the executable's dependencies.
    /// All of those dependencies are then copied to the destination directory.
    /// - Parameters:
    ///   - executable: The name of the exectable that you want to copy the dependencies for.
    ///   - packageDirectory: An URL that points to the executable's Package's directory
    ///   - destinationDirectory: The directory to copy the dependencies to. ie: `./build/lambda/$EXECUTABLE/`
    /// - Throws: if one of the steps fails.
    func copySwiftDependencies(for executable: String, at packageDirectory: URL, to destinationDirectory: URL, services: Servicable) throws {
        services.logger.trace("Copy Swift Dependencies: \(executable)")
        // Use ldd to get a list of Swift dependencies
        let dependencies = try getLddDependencies(for: executable, at: packageDirectory, services: services)
        // Iterate the URLs and copy the files
        try dependencies.forEach({
            try services.fileManager.copyItem(at: $0, to: destinationDirectory)
        })
    }
    
    /// Uses ldd within a Docker container to get a list of the executable's dependencies.
    /// - Parameters:
    ///   - executable: The name of the exectable that you want to copy the dependencies for.
    ///   - packageDirectory: An URL that points to the executable's Package's directory
    /// - Returns: An array of full path's to the dependencies.
    /// - Throws: if there is a problem getting the Swift dependencies.
    /// Output Example
    /// ```
    ///    linux-vdso.so.1 (0x00007fff84ba2000)
    ///    libswiftCore.so => /usr/lib/swift/linux/libswiftCore.so (0x00007fb41d09c000)
    /// ```
    func getLddDependencies(for executable: String, at packageDirectory: URL, services: Servicable) throws -> [URL] {
        let lddCommand = "ldd .build/release/\(executable)"
        let logs: [URL] = try Docker.runShellCommand(lddCommand, at: packageDirectory, logger: services.logger)
            .allEntries
            .map({ $0.message.trimmingCharacters(in: .whitespacesAndNewlines) }) // Get the raw message
            .filter({ $0.contains("swift") }) // Filter only the lines that contain "swift"
            .compactMap({ // Get the third column for each line
                let components = $0.components(separatedBy: " ")
                return components.first// [0] == "libswiftCore.so", [1] == "=>", [2] == "/usr/lib/swift/linux/libswiftCore.so", [3] == "(0x00007fb41d09c000)"
            })
            .map({ packageDirectory // Prefix the packageDirectory and ".build/release/" to the names to get the full path
                .appendingPathComponent(".build")
                .appendingPathComponent("release")
                .appendingPathComponent($0)
            })
        
        return logs
    }
    
    /// AWS Lambda requires a bootstrap file. It's simply a symlink to the executable to run.
    /// - Parameters:
    ///   - executable: The name of the exectable that you want to symlink
    ///   - packageDirectory: An URL that points to the executable's Package's directory
    /// - Returns: An array of full path's to the dependencies.
    /// - Throws: if there is a problem creating the symlink
    @discardableResult
    func addBootstrap(for executable: String, in destinationDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        services.logger.trace("Adding bootstrap: \(executable)")
        let command = "ln -s \(executable) bootstrap"
        let logs: LogCollector.Logs = try ShellExecutor.run(command)
        let errors = logs.allEntries.filter({ entry in
            return entry.level == .error
        })
        guard errors.count == 0 else {
            let messages = errors.compactMap({ $0.message }).joined(separator: "\n")
            throw PackageInDockerError.bootstrapFailure(messages)
        }
        return logs
    }
    
    /// After we copy everything to the destinationDirectory, we need to zip it all up.
    /// - Parameters:
    ///  - executable: The name of the executable that we are packaging up.
    ///  - destinationDirectory: The directory that we copied the files to.
    /// - Returns: The URL of the zip that we packaged everything into
    func archiveContents(for executable: String, in destinationDirectory: URL, services: Servicable) throws -> URL {
        // zip --symlinks $zipName * .env
        // echo -e "Built product at:\n$zipName"
        services.logger.trace("Archiving contents: \(executable)")
        let archive = archivePath(for: executable, in: destinationDirectory)
        let command = "zip --symlinks \(archive) * .env"
        let logs: LogCollector.Logs = try ShellExecutor.run(command)
        let errors = logs.allEntries.filter({ entry in
            return entry.level == .error
        })
        guard errors.count == 0 else {
            let messages = errors.compactMap({ $0.message }).joined(separator: "\n")
            throw PackageInDockerError.archivingFailure(messages)
        }
        return archive
    }
}


extension PackageInDocker {
    /// - Parameters
    ///   - executable: The built executable target that should be in the release directory
    /// - Returns: URL destination for packaging everything before we zip it up
    func URLForBuiltExecutable(_ executable: String) -> URL {
        return URL(fileURLWithPath: ".build")
            .appendingPathComponent("release")
            .appendingPathComponent(executable)
    }
    /// - Parameters
    ///   - executable: The executable target that we are packaging
    /// - Returns: URL destination for packaging everything before we zip it up
    func destinationURLForExecutable(_ executable: String) -> URL {
        return Self.destinationDirectory.appendingPathComponent(executable)
    }
    /// - Parameters
    ///   - packageDirectory:  The original directory of the package we are targeting
    ///   - executable: The executable target that we are packaging
    /// - Returns: URL destination for packaging everything before we zip it up
    func URLForEnvFile(packageDirectory: URL, executable: String) -> URL {
        return URL(fileURLWithPath: packageDirectory
                    .appendingPathComponent("Sources")
                    .appendingPathComponent(executable)
                    .appendingPathComponent(".env").path)
    }
    /// - Parameters
    ///   - executable: The executable target that we are packaging
    ///   - destinationDirectory: The directory that we are copying files to before zipping it up
    /// - Returns: URL destination for packaging everything before we zip it up
    func archivePath(for executable: String, in destinationDirectory: URL) -> URL {
        let timestamp = dateFormatter.string(from: Date())
        return destinationDirectory
            .appendingPathComponent("\(executable)_\(timestamp).zip")
    }
}
