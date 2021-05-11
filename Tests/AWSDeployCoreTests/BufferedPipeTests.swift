//
//  BufferedPipeTests.swift
//  
//
//  Created by Joel Saltzman on 5/7/21.
//

import Foundation
import XCTest
@testable import AWSDeployCore

class BufferedPipeTests: XCTestCase {
    
    func testPartialStringWrite() {
        // Given a partial String
        let data = "testing\n".data(using: .utf8)!
        let prefix = data.subdata(in: data.startIndex..<data.index(0, offsetBy: 4))
        let pipe = BufferedPipe(readabilityHandler: { string in
            XCTFail("Handler should not have been called")
        })

        // When write is called
        pipe.fileHandleForWriting.write(prefix)
        
        // Then the read handler should not be called
        RunLoop.current.run(until: Date.init(timeIntervalSinceNow: 0.5))
    }
    func testFullString() {
        // Given a full String
        let data = "testing\n".data(using: .utf8)!
        let handlerCalled = expectation(description: "Read handler called")
        let pipe = BufferedPipe(readabilityHandler: { string in
            XCTAssertEqual(string, "testing\n")
            handlerCalled.fulfill()
        })

        // When write is called
        pipe.fileHandleForWriting.write(data)
        
        // Then the read handler should be called
        wait(for: [handlerCalled], timeout: 2.0)
    }
    func testDeallocation() {
        // Give a BufferedPipe
        var pipe: BufferedPipe? = BufferedPipe(readabilityHandler: { string in
            XCTFail("Handler should not have been called")
        })

        // When write is called before being deallocated
        pipe?.fileHandleForWriting.write("example \n".data(using: .utf8)!)
        pipe = nil
        
        // Then the read handler should not be called
        RunLoop.current.run(until: Date.init(timeIntervalSinceNow: 0.5))
    }
}
