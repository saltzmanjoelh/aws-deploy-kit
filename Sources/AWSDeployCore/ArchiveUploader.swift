//
//  Uploader.swift
//  
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import LogKit
import Logging
import SotoS3
import NIO

public enum ArchiveUploaderError: Error, CustomStringConvertible {
    case archiveDoesNotExist(String)
    
    public var description: String {
        switch self {
        case .archiveDoesNotExist(let path):
            return "The archive at path: \(path) could not be found."
        }
    }
}


public struct ArchiveUploader {
    
    public init() {}
    
    /// Verifies that the bucket exists. If it doesn't, it will be created.
    /// - Parameters:
    ///   - bucket: Name of the bucket to verify.
    ///   - s3: S3 service to verify with
    ///   - logger: Logger
    /// - Returns: Future name of the bucket
    public func verifyBucket(_ bucket: String, services: Servicable) throws -> EventLoopFuture<String> {
        services.logger.info("Checking if bucket exists: \(bucket)")
        return services.s3.headBucket(.init(bucket: bucket))
            .map({ _ in
                services.logger.info("Bucket exists")
                return bucket
            })
            .flatMapError { (error: Error) -> EventLoopFuture<String> in
                services.logger.info("Bucket does not exist. Creating the bucket.")
                return services.s3.createBucket(.init(bucket: bucket))
                    .map({ _ in
                        services.logger.info("Created bucket: \(bucket)")
                        return bucket
                    })
            }
    }
    
    /// Upload archives to an S3 bucket.
    /// - Parameters:
    ///   - archivePaths: Paths to the archives you want to load.
    ///   - bucket: Name of the bucket you want to upload to.
    ///   - s3: S3 service to upload with
    /// - Returns: Tuple of (Archive Path, Version Id) Version Id is available with a successful upload.
    public func uploadArchives(_ archiveURLs: [URL],
                               bucket: String,
                               services: Servicable) throws -> EventLoopFuture<[(String, String?)]> {
        services.logger.info("Upload archives to bucket: \(bucket). Archives: \(archiveURLs)")
        
        // Create an array of upload futures
        let futures = try archiveURLs.map { (archive: URL) -> EventLoopFuture<S3.PutObjectOutput> in
            guard let data = FileManager.default.contents(atPath: archive.absoluteString),
                  data.count > 0
            else { throw ArchiveUploaderError.archiveDoesNotExist(archive.absoluteString) }
            return services.s3.putObject(.init(body: .data(data),
                                          bucket: bucket,
                                          key: archive.lastPathComponent))
        }
        // Make sure that the bucket exists, then upload all the archives
        return try verifyBucket(bucket, services: services)
            .flatMap { _ -> EventLoopFuture<[(String, String?)]> in
                return EventLoopFuture.reduce(into: Array<(String, String?)>(),
                                              futures,
                                              on: services.s3.client.eventLoopGroup.next()) { (result, nextValue) in
                    let archive = archiveURLs[result.count]
                    result.append((archive.absoluteString, nextValue.versionId))
                    services.logger.info("Uploaded archive: \(archive.lastPathComponent) version: \(nextValue.versionId ?? "Empty")")
                }
            }
    }
}
