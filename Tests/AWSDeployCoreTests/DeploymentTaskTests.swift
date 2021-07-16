//
//  DeploymentTaskTests.swift
//  
//
//  Created by Joel Saltzman on 7/11/21.
//

import Foundation
import XCTest
import AWSDeployCore
import SotoLambda
import Mocking

class DeploymentTaskTests: XCTestCase {
    
    struct Task: DeploymentTask {
        static var functionName: String { "test-task" }
        var functionName: String { Self.functionName }
        
        @ThrowingMock
        var buildSetUpMock = { () throws -> Void in
        }
        func buildSetUp() throws {
            try $buildSetUpMock.getValue(Void())
        }

        @Mock
        var testSetUpMock = { () -> EventLoopFuture<Void> in
            return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void())
        }
        func testSetUp() -> EventLoopFuture<Void> {
            return $testSetUpMock.getValue(Void())
        }

        @Mock
        var testTearDownMock = { () -> EventLoopFuture<Void> in
            return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void())
        }
        func testTearDown() -> EventLoopFuture<Void> {
            return $testTearDownMock.getValue(Void())
        }
        
        @ThrowingMock
        var createInvocationTaskMock = { () throws -> InvocationTask in
            return InvocationTask.init(functionName: Self.functionName, payload: "", verifyResponse: { _ in return true })
        }
        func createInvocationTask() throws -> InvocationTask {
            return try $createInvocationTaskMock.getValue(Void())
        }
    }
    
    var mockServices: MockServices!
    
    override func setUp() {
        continueAfterFailure = false
        mockServices = MockServices()
    }
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        mockServices.cleanup()
        try cleanupTestPackage()
    }
    
    func testDeploy() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        mockServices.mockBuilder.prepareDocker = { _ in }
        mockServices.mockBuilder.buildAndPackage = { _ in return URL(fileURLWithPath: "/path/to/\(Task.functionName).zip") }
        mockServices.mockPublisher.publishFunctionCode = { _ in self.mockServices.stubFunctionConfiguration(functionName: Task.functionName)
        }
        mockServices.mockPublisher.publishLatest = { _ in
            self.mockServices.stubFunctionConfiguration(functionName: Task.functionName)
        }
        mockServices.mockInvoker.invoke = { _ -> EventLoopFuture<Data> in
            self.mockServices.lambda.eventLoopGroup.next().makeSucceededFuture(Data())
        }
        mockServices.mockPublisher.updateAliasVersion = { _ in
            self.mockServices.stubAliasConfiguration(alias: Publisher.defaultAlias)
        }
        // Given an array of DeploymentTasks
        let task = Task()
        let tasks: [DeploymentTask] = [task]
        
        // When calling deploy
        _ = try tasks.deploy(from: packageDirectory, services: mockServices).wait()
        
        // Then the implemented DeploymentTask functions are called
        XCTAssertTrue(mockServices.mockBuilder.$buildAndPackage.wasCalled, "buildProducts should have been called.")
        XCTAssertTrue(mockServices.mockPublisher.$publishArchive.wasCalled, "publishArchive should have been called.")
        XCTAssertTrue(task.$buildSetUpMock.wasCalled, "buildSetUp was not called.")
        XCTAssertTrue(task.$testSetUpMock.wasCalled, "testSetUp was not called.")
        XCTAssertTrue(task.$testTearDownMock.wasCalled, "testTearDown was not called.")
        XCTAssertTrue(task.$createInvocationTaskMock.wasCalled, "createInvocationTask was not called.")
        
    }
    
    func testDeploymentTaskDefaultImplementation() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        mockServices.mockBuilder.prepareDocker = { _ in }
        mockServices.mockBuilder.buildAndPackage = { _ in return URL(fileURLWithPath: "/path/to/\(Task.functionName).zip") }
        mockServices.mockPublisher.publishFunctionCode = { _ in self.mockServices.stubFunctionConfiguration(functionName: Task.functionName)
        }
        mockServices.mockPublisher.publishLatest = { _ in
            self.mockServices.stubFunctionConfiguration(functionName: Task.functionName)
        }
        mockServices.mockInvoker.invoke = { _ -> EventLoopFuture<Data> in
            self.mockServices.lambda.eventLoopGroup.next().makeSucceededFuture(Data())
        }
        mockServices.mockPublisher.updateAliasVersion = { _ in
            self.mockServices.stubAliasConfiguration(alias: Publisher.defaultAlias)
        }
        // Given a DeploymentTask that does not override buildSetUp, testSetUp and testTearDown
        struct MyTask: DeploymentTask {
            var functionName: String = "custom"
            
            @ThrowingMock
            var createInvocationTaskMock = { () throws -> InvocationTask in
                return InvocationTask.init(functionName: "", payload: "", verifyResponse: { _ in return true })
            }
            func createInvocationTask() throws -> InvocationTask {
                return try $createInvocationTaskMock.getValue(())
            }
        }
        let task = MyTask()
        
        // When calling deploy
        _ = try [task].deploy(from: packageDirectory, services: mockServices).wait()

        // Then the default DeploymentTask functions are called
        XCTAssertTrue(mockServices.mockBuilder.$buildAndPackage.wasCalled, "buildProducts should have been called.")
        XCTAssertTrue(mockServices.mockPublisher.$publishArchive.wasCalled, "publishArchive should have been called.")
        XCTAssertTrue(task.$createInvocationTaskMock.wasCalled, "createInvocationTask was not called.")
        // This is more for code coverage
    }
}
