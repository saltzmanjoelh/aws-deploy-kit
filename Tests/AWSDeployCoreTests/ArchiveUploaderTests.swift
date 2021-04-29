//
//  ArchiveUploaderTests.swift
//  
//
//  Created by Joel Saltzman on 3/26/21.
//

import Foundation
import XCTest
import Logging
import LogKit
import NIOHTTP1
import AsyncHTTPClient
import SotoTestUtils
import SotoS3
import XcodeTestingKit
@testable import AWSDeployCore

class ArchiveUploaderTests: XCTestCase {
    
    func testVerifyBucketExists() throws {
        // Use log collector to check for "Bucket exists"
        // Given a valid bucket
        let bucket = "bucket-name"
        let instance = ArchiveUploader()
        let testServices = TestServices()
        let resultReceived = expectation(description: "Result received")
        
        // When calling verifyBucket
        let future = try instance.verifyBucket(bucket, services: testServices)
        future.whenSuccess { (result: String) in
            XCTAssertEqual(result, bucket)
            resultReceived.fulfill()
        }
        
        try testServices.awsServer.processRaw { request in
            return .result(.ok)
        }
        // Then "Bucket exists" should be logged
        wait(for: [resultReceived], timeout: 2.0)
        let message = testServices.logCollection.allEntries.map({ $0.message })
        XCTAssertTrue(message.contains(where: { $0 == "Bucket exists"}))
    }
    func testVerifyBucketCreation() throws {
        // Use log collector to check for "Created bucket: \(bucket)"
        // Given a valid bucket
        let bucket = "bucket-name"
        let instance = ArchiveUploader()
        let testServices = TestServices()
        let resultReceived = expectation(description: "Result received")
        
        // When calling verifyBucket
        let future = try instance.verifyBucket(bucket, services: testServices)
        future.whenSuccess { (result: String) in
            XCTAssertEqual(result, bucket)
            resultReceived.fulfill()
        }
        
        try testServices.awsServer.processRaw { request in
            if request.method == .HEAD {
                return .result(.init(httpStatus: HTTPResponseStatus.init(statusCode: 404)), continueProcessing: true)
            }
            return .result(.ok)
        }
        // Then "Created bucket:" should be logged
        wait(for: [resultReceived], timeout: 2.0)
        let message = testServices.logCollection.allEntries.map({ $0.message })
        XCTAssertTrue(message.contains(where: { $0 == "Created bucket: \(bucket)"}))
    }
    
    func testUploadArchives() throws {
        // Setup
        let testServices = TestServices()
        let archivePath = "/tmp/archive.zip"
        FileManager.default.createFile(atPath: archivePath, contents: "File".data(using: .utf8)!, attributes: nil)
        
        // Given valid file paths
        let urls = [URL(string: archivePath)!]
        let instance = ArchiveUploader()

        // When calling uploadArchives
        let future = try instance.uploadArchives(urls, bucket: "bucket-name", services: testServices)

        
        future.whenComplete { (result: Result<[(String, String?)], Error>) in
            do {
                // Then we should receive version ids for the uploaded archives
                let items = try result.get().map({ $0.0 })
                XCTAssertEqual(items, [archivePath])
            } catch {
                XCTFail(error)
            }
        }
        
        var actions = 2 // Create bucket and upload archive
        try testServices.awsServer.processRaw { request in
            actions -= 1
            return .result(.ok, continueProcessing: actions > 0)
        }
        XCTAssertEqual(actions, 0, "Not all calls were performed.")
    }
    func testUploadArchivesHandlesInvalidArchivePath() throws {
        // Given an invalid file path
        let archivePath = "/...."
        let urls = [URL(string: archivePath)!]
        let instance = ArchiveUploader()

        
        do {
            // When calling uploadArchives
            _ = try instance.uploadArchives(urls, bucket: "bucket-name", services: TestServices())
            XCTFail("An error should have been thrown.")
        } catch {
            
            // Then an archiveDoesNotExist should be thrown
            XCTAssertEqual("\(error)", ArchiveUploaderError.archiveDoesNotExist(archivePath).description)
        }
    }
    func testUploadArchivesHandlesMissingArchive() throws {
        // Given an invalid file path
        let archivePath = "/tmp/invalid"
        let urls = [URL(string: archivePath)!]
        let instance = ArchiveUploader()

        do {
            // When calling uploadArchives
            _ = try instance.uploadArchives(urls, bucket: "bucket-name", services: TestServices())
            XCTFail("An error should have been thrown.")
        } catch {
            
            // Then an archiveDoesNotExist should be thrown
            XCTAssertEqual("\(error)", ArchiveUploaderError.archiveDoesNotExist(archivePath).description)
        }
    }
}
