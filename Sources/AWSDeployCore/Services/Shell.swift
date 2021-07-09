//
//  ShellExecutor.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import Logging
import LogKit
import Mocking

public protocol ShellExecutable {
    func run(
        _ command: String,
        at workingDirectory: URL?,
        logger: Logger?
    ) throws -> LogCollector.Logs
    
    func run(
        _ command: String,
        at workingDirectory: URL?,
        logger: Logger?
    ) throws -> String
    
    func launchShell(command: String, at workingDirectory: URL, logger: Logger?) throws -> LogCollector.Logs
}

extension ShellExecutable {
    /// Executes a shell script and returns both the stdout and stderr UTF8 Strings combined as a single String.
    @discardableResult
    public func run(_ command: String, at workingDirectory: URL? = nil, logger: Logger? = nil) throws -> String {
        let output = try run(command, at: workingDirectory, logger: logger).allMessages(joined: "")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Executes a shell script and returns the raw `LogCollector.Logs`.
    /// stdout messages have .trace LogLevel and stderr have .error LogLevel.
    @discardableResult
    public func run(_ command: String, at workingDirectory: URL? = nil, logger: Logger? = nil) throws -> LogCollector.Logs {
        let currentDirectory = workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        logger?.trace("Running shell command: \(command) at: \(currentDirectory.path)")
        return try launchShell(command: command, at: currentDirectory, logger: logger)
    }
}

// MARK: - Shell
public struct Shell: ShellExecutable {
    public init() {}
    
    public func launchShell(command: String, at workingDirectory: URL, logger: Logger?) throws -> LogCollector.Logs {
        let process = Process.init()
        return try process.launchBash(command, at: workingDirectory, logger: logger)
    }
}



// MARK: - ShellOut
/// Modified version of [Shellout](https://github.com/JohnSundell/ShellOut)
/// We return both stdout + stderr as the in the LogCollector.Logs
/// stdout messages have .trace LogLevel and stderr have .error LogLevel.
extension Process {
    @discardableResult func launchBash(_ shellCommand: String,
                                       at workingDirectory: URL,
                                       logger: Logger? = nil) throws -> LogCollector.Logs {
        self.currentDirectoryPath = workingDirectory.path
        self.launchPath = "/bin/bash"
        self.arguments = ["-c", shellCommand]
        

        // Because FileHandle's readabilityHandler might be called from a
        // different queue from the calling queue, avoid a data race by
        // protecting reads and writes on a single dispatch queue.
        let outputQueue = DispatchQueue(label: "bash-output-queue")
        
        let logs = LogCollector.Logs()
        let stdoutPipe = BufferedPipe() { message in
            outputQueue.async {
                if let log = Self.appendLog(message, level: .trace, logs: logs) {
                    logger?.trace(log)
                }
            }
        }
        let stderrPipe = BufferedPipe() { message in
            outputQueue.async {
                if let log = Self.appendLog(message, level: .error, logs: logs) {
                    logger?.error(log)
                }
            }
        }
        standardOutput = stdoutPipe.internalPipe
        standardError = stderrPipe.internalPipe

        launch()

        waitUntilExit()


        // Block until all writes have occurred
        return try outputQueue.sync {
            if terminationStatus != 0 {
                throw ShellOutError(
                    terminationStatus: terminationStatus,
                    output: logs.allMessages(joined: "")
                )
            }
            return logs
        }
    }
    static func appendLog(_ message: String, level: Logger.Level, logs: LogCollector.Logs) -> Logger.Message? {
        guard message.count > 0 else { return nil }
        let logMessage: Logger.Message = .init(stringLiteral: "\(message)")
        logs.append(level: level,
                    message: logMessage,
                    metadata: nil)
        return logMessage
    }
}

// MARK: - ShellOutError
/// Error type thrown by the `shellOut()` function, in case the given command failed
public struct ShellOutError: Swift.Error {
    /// The termination status of the command that was run
    public let terminationStatus: Int32
    /// All output that was recevied during the execution
    public var output: String
}

extension ShellOutError: CustomStringConvertible {
    public var description: String {
        return """
               ShellOut encountered an error
               Status code: \(terminationStatus)
               Output: "\(output)"
               """
    }
}
