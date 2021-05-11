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
    
    /// Executes a shell script and return the stdout and stderr UTF8 Strings.
    /// ShellOut only returns the stdout data. We also want stderr data
    /// because some apps don't terminate with an error but return successfully
    /// and have error output.
    @discardableResult
    public static func run(
        _ command: String,
        arguments: [String] = [],
        at path: String = ".",
        logger: Logger? = nil
    ) throws -> String {
        let shellCommand = "cd \(path.escapingSpaces) && \(command) \(arguments.joined(separator: " "))"
        logger?.trace("Running shell command: \(shellCommand)")
        let output = try Self.shellOutAction(shellCommand, logger)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Testing Helpers
extension ShellExecutor {
    
    /// The function to perform the shellOut action. You only need to modify this for tests.
    /// You could set this to a custom closure that simply returns a fixed String to test how
    /// your code handles specific output. Make sure to reset it for the next test though.
    /// ```swift
    /// ShellExecutor.shellOutAction = { _, _, _, _ in return "File not found." }
    /// defer { ShellExecutor.resetAction() }
    /// ```
    public static var shellOutAction: (String, Logger?) throws -> String = Self.defaultAction
    
    public static func resetAction() {
        Self.shellOutAction = defaultAction
    }
    /// The default action we perform is Process.launchBash(_:arguments:at:logger:)
    private static let defaultAction = { (shellCommand: String, logger: Logger?) throws -> String in
        let process = Process.init()
        return try process.launchBash(with: shellCommand, logger: logger)
    }
}


// MARK: - ShellOut
/// Modified version of [Shellout](https://github.com/JohnSundell/ShellOut)
/// We return both stdout + stderr as the result.
private extension Process {
    @discardableResult func launchBash(with command: String, logger: Logger?) throws -> String {
        launchPath = "/bin/bash"
        arguments = ["-c", command]

        // Because FileHandle's readabilityHandler might be called from a
        // different queue from the calling queue, avoid a data race by
        // protecting reads and writes on a single dispatch queue.
        let outputQueue = DispatchQueue(label: "bash-output-queue")

        var messages = [String]()
        let outPipe = BufferedPipe() { message in
            guard message.count > 0 else { return }
            outputQueue.async {
                messages.append(message)
                logger?.trace(.init(stringLiteral: "\(message)"))
            }
        }
        standardOutput = outPipe.internalPipe
        standardError = outPipe.internalPipe

        launch()

        waitUntilExit()


        // Block until all writes have occurred
        return try outputQueue.sync {
            let output = messages.joined(separator: "")
            if terminationStatus != 0 {
                throw ShellOutError(
                    terminationStatus: terminationStatus,
                    output: output
                )
            }
            return output
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
