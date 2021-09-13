//
//  Docker.swift
//  
//
//  Created by Joel Saltzman on 5/17/21.
//

import Foundation
import Logging
import LogKit

public enum Docker {
    public struct Config {
        public static let imageName = "swiftlang/swift:nightly-5.5-amazonlinux2"//"swift:5.4-amazonlinux2"
        public static let containerName = "awsdeploykit-builder"
    }
    static func runShellCommand(_ shellCommand: String, at packageDirectory: URL, services: Servicable) throws -> LogCollector.Logs {
        let shellCommand = createShellCommand(shellCommand, at: packageDirectory, services: services)
        return try services.shell.run(
            shellCommand,
            at: packageDirectory,
            logger: services.logger
        )
    }
    static func createShellCommand(_ shellCommand: String, at packageDirectory: URL, services: Servicable) -> String {
        let dockerCommand = "/usr/local/bin/docker"
        var arguments = [
            "run",
            "-it",
            "--rm",
            "-e",
            "TERM=dumb",
            "-e",
            "GIT_TERMINAL_PROMPT=1",
            "-v",
            "\(packageDirectory.path):\(packageDirectory.path)",
            "-w",
            packageDirectory.path,
        ]
        if let sshDirectory = getSSHDirectory(services: services) {
            // We can't mount the directory path with ~/.ssh/
            // we have to use a full path with Docker. So we mount the macOS path
            // then we issue a copy command to the user's .ssh directory.
            let sshCommand: [String] = [
                "mkdir -p ~/.ssh/",
                "cp \(sshDirectory.appendingPathComponent("*").path) ~/.ssh/"
            ]
            let volumeMounts = [
                "-v", "\(sshDirectory.path):\(sshDirectory.path)",
            ]
            let command = sshCommand + [shellCommand]
            let commandString = "\"\(command.joined(separator: " && "))\""
            arguments += volumeMounts + [Docker.Config.containerName] + ["ssh-agent", "bash", "-c"] + [commandString]
            
        } else {
            arguments += [
                Docker.Config.containerName,
                "/usr/bin/bash",
                "-c",
                "\"\(shellCommand)\"",
            ]
        }
        let shellCommand = ([dockerCommand] + arguments).joined(separator: " ")
        return shellCommand
    }
    
    
    /// Check if user's .ssh directory exists. We neeed this for repos where the username
    /// of a private repo are in the config file and we have a private key to access the repo.
    /// - Parameter services: The set of services which will be used to execute your request with.
    /// - Returns: URL to ~/.ssh
    static func getSSHDirectory(services: Servicable) -> URL? {
        let home = services.fileManager.usersHomeDirectory
        let ssh = home.appendingPathComponent(".ssh")
        return services.fileManager.fileExists(atPath: ssh.path) ? ssh : nil
    }
}

