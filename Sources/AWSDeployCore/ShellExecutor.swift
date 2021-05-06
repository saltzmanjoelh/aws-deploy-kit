//
//  ShellExecutor.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import Logging
import LogKit
import ShellOut

public enum ShellExecutor {
    /// The function to perform the shellOut action. You only need to modify this for tests.
    public static var shellOutAction: (String, [String], String, Process, FileHandle?, FileHandle?) throws -> String = shellOut(to:arguments:at:process:outputHandle:errorHandle:)
    /// Executes a shell script
    @discardableResult
    public static func run(
        _ command: String,
        arguments: [String] = [],
        at path: String = ".",
        process: Process = .init(),
        outputHandle: FileHandle? = nil,
        errorHandle: FileHandle? = nil,
        logger: Logger? = nil
    ) throws -> String {
        let cmd = ([command] + arguments).joined(separator: " ")
        logger?.trace("Running shell command: \(cmd)")
        let output = try shellOutAction(command, arguments, path, process, outputHandle, errorHandle)
        logger?.trace("\(output)")
        return output
    }
}
