//
//  ShellExecutor.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import Logging
import LogKit

public enum ShellExecutor {
    
    /// Executes a shell script and returns both the stdout and stderr UTF8 Strings combined as a single String.
    @discardableResult
    public static func run(
        _ command: String,
        arguments: [String] = [],
        at path: String = ".",
        logger: Logger? = nil
    ) throws -> String {
        let output = try run(command, arguments: arguments, at: path, logger: logger).allMessages(joined: "")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Executes a shell script and returns the raw `LogCollector.Logs`.
    /// stdout messages have .trace LogLevel and stderr have .error LogLevel.
    @discardableResult
    public static func run(
        _ command: String,
        arguments: [String] = [],
        at path: String = ".",
        logger: Logger? = nil
    ) throws -> LogCollector.Logs {
        let shellCommand = "\(command) \(arguments.joined(separator: " "))"
        logger?.trace("Running shell command: \(shellCommand) at: \(path)")
        return try Self.shellOutAction(shellCommand, path, logger)
    }
}

// MARK: - Testing Helpers
extension ShellExecutor {
    
    /// The function to perform the shellOut action. You only need to modify this for tests.
    /// You could set this to a custom closure that simply returns a fixed String to test how
    /// your code handles specific output. Make sure to reset it for the next test though.
    /// ```swift
    /// ShellExecutor.shellOutAction = { _, _, _ in return "File not found." }
    /// defer { ShellExecutor.resetAction() }
    /// ```
    public static var shellOutAction: (String, String, Logger?) throws -> LogCollector.Logs = Self.defaultAction
    
    public static func resetAction() {
        Self.shellOutAction = defaultAction
    }
    /// The default action we perform is Process.launchBash(_:arguments:at:logger:)
    private static let defaultAction = { (command: String, path: String, logger: Logger?) throws -> LogCollector.Logs in
        let process = Process.init()
        return try process.launchBash(command, at: path, logger: logger)
    }
}


// MARK: - ShellOut
/// Modified version of [Shellout](https://github.com/JohnSundell/ShellOut)
/// We return both stdout + stderr as the in the LogCollector.Logs
/// stdout messages have .trace LogLevel and stderr have .error LogLevel.
private extension Process {
    @discardableResult func launchBash(_ shellCommand: String,
                                       at path: String = ".",
                                       logger: Logger? = nil) throws -> LogCollector.Logs {
        self.currentDirectoryPath = path
        self.launchPath = "/bin/bash"
        self.arguments = ["-c", "cd \(path) && \(shellCommand)"]
        

        // Because FileHandle's readabilityHandler might be called from a
        // different queue from the calling queue, avoid a data race by
        // protecting reads and writes on a single dispatch queue.
        let outputQueue = DispatchQueue(label: "bash-output-queue")
        
        let logs = LogCollector.Logs()
        let stdoutPipe = BufferedPipe() { message in
            guard message.count > 0 else { return }
            outputQueue.async {
                let logMessage: Logger.Message = .init(stringLiteral: "\(message)")
                logger?.trace(logMessage)
                logs.append(level: .trace,
                            message: logMessage,
                            metadata: nil)
            }
        }
        let stderrPipe = BufferedPipe() { message in
            guard message.count > 0 else { return }
            outputQueue.async {
                let logMessage: Logger.Message = .init(stringLiteral: "\(message)")
                logger?.error(logMessage)
                logs.append(level: .error,
                            message: logMessage,
                            metadata: nil)
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
}

private extension String {
    var escapingSpaces: String {
        return replacingOccurrences(of: " ", with: "\\ ")
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
