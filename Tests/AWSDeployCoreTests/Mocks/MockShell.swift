//
//  MockShell.swift
//  
//
//  Created by Joel Saltzman on 6/22/21.
//

import Foundation
import Mocking
import Logging
import LogKit
@testable import AWSDeployCore

public struct MockShell: ShellExecutable {
    public func launchShell(command: String, at workingDirectory: URL, logger: Logger?) throws -> LogCollector.Logs {
        return try _launchShell.getValue(EquatableTuple([CodableInput(command), CodableInput(workingDirectory)]))
    }
    
    /// The function to perform in bash. You can modify this for tests.
    /// You could set this to a custom closure that simply returns a fixed String to test how
    /// your code handles specific output. Make sure to reset it for the next test though.
    /// ```swift
    /// ShellExecutor.shellOutAction = { _, _, _ in return "File not found." }
    /// defer { ShellExecutor.resetAction() }
    /// ```
    @ThrowingMock
    public var launchShell = { (tuple: EquatableTuple<CodableInput>) throws -> LogCollector.Logs in
        let process = Process.init()
        return try process.launchBash(try tuple.inputs[0].decode(), at: try tuple.inputs[1].decode(), logger: nil)
    }
}
