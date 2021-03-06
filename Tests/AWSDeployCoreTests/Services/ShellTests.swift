//
//  ShellExecutorTestss.swift
//  
//
//  Created by Joel Saltzman on 5/10/21.
//

import Foundation
import XCTest
import Logging
import LogKit
@testable import AWSDeployCore

class ShellExecutorTests: XCTestCase {
    
    override func setUp() {
        continueAfterFailure = false
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        try cleanupTestPackage()
    }
    
    func testAppendLogHandlesEmptyMessage() {
        let logs = LogCollector.Logs()
        let message = Process.appendLog("", level: .error, logs: logs)
        XCTAssertNil(message)
        XCTAssertEqual(logs.allEntries.count, 0)
    }
    
    func testStdOut() throws {
        let testServices = MockServices()
        let cmd = "echo \"stdout\""
        let output: String = try Shell().run(cmd, logger: testServices.logger)
        XCTAssertString(output, contains: "stdout")
        let messages = testServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "stdout\n")
    }
    func testStdErr() throws {
        let testServices = MockServices()
        let cmd = "echo \"stderr\" >> /dev/stderr"
        let output: String = try Shell().run(cmd, logger: testServices.logger)
        XCTAssertString(output, contains: "stderr")
        let messages = testServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "stderr\n")
    }
    func testStdOutAndStdErrCombinedOutput() throws {
        // Messages printed to stderr should be included in the output
        let testServices = MockServices()
        let cmd = "echo \"stdout\" >> /dev/stdout && echo \"stderr\" >> /dev/stderr"
        let output: String = try Shell().run(cmd, logger: testServices.logger)
        XCTAssertString(output, contains: "stdout")
        XCTAssertString(output, contains: "\n")
        XCTAssertString(output, contains: "stderr")
        let messages = testServices.logCollector.logs.allMessages()
        XCTAssertString(messages, contains: "stdout\n")
        XCTAssertString(messages, contains: "stderr\n")
    }
    func testAbnormalTerminationIsHandled() throws {
        // Give a command that terminates with a non-zero status
        let command = "invalid-app"
        
        do {
            // When calling run()
            let _: String = try Shell().run(command)
            
            XCTFail("An error should have been thrown.")
        } catch let error as ShellOutError {
            // Then an ShellOutError should be thrown
            XCTAssertEqual(error.terminationStatus, 127)
            XCTAssertTrue(error.output.contains("command not found"), "Output: \(error.output) should have contained: \"command not found\".")
            XCTAssertTrue(error.description.contains("command not found"), "errorDescription: \(error.output) should have contained: \"command not found\".")
        } catch {
            XCTFail(error)
        }
    }
    func testNoOutputIsHandled() throws {
        // Give a command that terminates with a non-zero status
        let command = "true"
        
        do {
            // When calling run()
            let _: String = try Shell().run(command)
        } catch let error as ShellOutError {
            // Then an ShellOutError should be thrown
            XCTAssertEqual(error.terminationStatus, 127)
        } catch {
            XCTFail(error)
        }
    }
    
}
