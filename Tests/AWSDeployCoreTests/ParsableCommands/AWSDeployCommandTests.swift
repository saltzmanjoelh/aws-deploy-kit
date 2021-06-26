//
//  AWSDeployCommandTests.swift
//  
//
//  Created by Joel Saltzman on 6/21/21.
//

import Foundation
import XCTest
import Logging
import LogKit
import NIO
import SotoLambda
@testable import AWSDeployCore
@testable import SotoTestUtils

class AWSDeployCommandTests: XCTestCase {
    
    func testInit() throws {
        // This is simply for coverage
        _ = AWSDeployCommand()
    }
}
