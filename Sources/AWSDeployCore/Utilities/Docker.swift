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
        public static let imageName = "swift:5.3-amazonlinux2"
        public static let containerName = "awsdeploykit-builder"
    }
    static func runShellCommand(_ shellCommand: String, at packageDirectory: URL, services: Servicable, sshPrivateKeyPath: URL? = nil) throws -> LogCollector.Logs {
        let shellCommand = createShellCommand(shellCommand, at: packageDirectory, sshPrivateKeyPath: sshPrivateKeyPath)
        return try services.shell.run(
            shellCommand,
            at: packageDirectory,
            logger: services.logger
        )
    }
    static func createShellCommand(_ shellCommand: String, at packageDirectory: URL, sshPrivateKeyPath: URL? = nil) -> String {
        let dockerCommand = "/usr/local/bin/docker"
        var arguments = [
            "run",
            "-i",
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
        if let privateKeyPath = sshPrivateKeyPath {
            // We need the path to the key mounted and
            // need to use the ssh-agent command
            arguments += [
                "-v",
                "\(privateKeyPath.path):\(privateKeyPath.path)",
                Docker.Config.containerName,
                "ssh-agent",
                "bash",
                "-c",
                "ssh-add -c \(privateKeyPath.path); \(shellCommand)",
            ]
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
}

