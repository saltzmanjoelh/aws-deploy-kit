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
        
        static var functionName: String { ExamplePackage.executableOne.name }
        
        var functionName: String { Self.functionName }
        
        func buildSetUp(services: Servicable) throws {
            try $buildSetUpMock.getValue(Void())
        }
        func invocationSetUp(services: Servicable) -> EventLoopFuture<Void> {
            return $invocationSetUpMock.getValue(Void())
        }
        
        func invocationPayload() throws -> String {
            return ""
        }
        
        func verifyInvocation(_ data: Data) throws -> Void {
            /* valid */
        }
        
        func invocationTearDown(services: Servicable) -> EventLoopFuture<Void> {
            return $invocationTearDownMock.getValue(Void())
        }
        
        
        // The mocks don't do anything but they keep track of their usage
        // so we can make sure that they were called as expected.
        @ThrowingMock
        var buildSetUpMock = { () throws -> Void in
        }
        @Mock
        var invocationSetUpMock = { () -> EventLoopFuture<Void> in
            return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void())
        }
        @Mock
        var invocationTearDownMock = { () -> EventLoopFuture<Void> in
            return Services.shared.lambda.eventLoopGroup.next().makeSucceededFuture(Void())
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
        mockServices.mockBuilder.loadProducts = { _ in return ExamplePackage.products }
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
        XCTAssertTrue(task.$invocationSetUpMock.wasCalled, "testSetUp was not called.")
        XCTAssertTrue(task.$invocationTearDownMock.wasCalled, "testTearDown was not called.")
        
    }
    
    func testDeploymentTaskDefaultImplementation() throws {
        // Setup
        let packageDirectory = try createTempPackage()
        mockServices.mockBuilder.loadProducts = { _ in return ExamplePackage.products }
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
            var functionName: String = ExamplePackage.executableOne.name
            func invocationPayload() throws -> String {
                return ""
            }
            func verifyInvocation(_ data: Data) throws -> Void {
                /* valid */
            }
        }
        let task = MyTask()
        
        // When calling deploy
        _ = try [task].deploy(from: packageDirectory, services: mockServices).wait()

        // Then the default DeploymentTask functions are called
        XCTAssertTrue(mockServices.mockBuilder.$buildAndPackage.wasCalled, "buildProducts should have been called.")
        XCTAssertTrue(mockServices.mockPublisher.$publishArchive.wasCalled, "publishArchive should have been called.")
        // This is more for code coverage
    }
}
