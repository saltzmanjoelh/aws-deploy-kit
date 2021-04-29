//
//  BlueGreenPublisher.swift
//  
//
//  Created by Joel Saltzman on 3/25/21.
//

import Foundation
import LogKit
import Logging
import SotoLambda
import SotoS3
import NIO
import AWSLambdaKit
import AWSLambdaEvents

public enum BlueGreenPublisherError: Error, CustomStringConvertible {
    case archiveDoesNotExist(String)
    case invokeLambdaFailed(String, String)
    case invalidArchiveName(String)
    case invalidFunctionConfiguration(String, String)
    
    public var description: String {
        switch self {
        case .archiveDoesNotExist(let path):
            return "The archive at path: \(path) could not be found."
        case .invokeLambdaFailed(let functionName, let message):
            return "There was an error invoking the \(functionName) lambda. Message: \(message))"
        case .invalidArchiveName(let path):
            return "Invalid archive name: \(path). It should be in the format: $executable_yyyymmdd_HHMM.zip"
        case .invalidFunctionConfiguration(let field, let source):
            return "Invalid FunctionConfiguration. Required field \"\(field)\" was missing in \(source)."
        }
    }
}

public struct BlueGreenPublisher {
    
    public init(){}
    
    /// Creates a new Lambda function. Then, invokes the function to make sure that it's not crashing.
    /// Finally, points the API Gateway to the new Lambda function.
    public func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        let futures = archiveURLs.map({ self.publishArchive($0, services: services) })
        return EventLoopFuture.reduce(into: Array<Lambda.AliasConfiguration>(),
                                      futures,
                                      on: services.lambda.client.eventLoopGroup.next()) { (result, nextValue) in
            result.append(nextValue)
            services.logger.info("Updated: \(nextValue)")
        }
    }
    
    public func publishArchive(_ archiveURL: URL, alias: String = "production", services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        services.logger.info("Publishing: \(archiveURL.lastPathComponent)")
        return self.getFunctionConfiguration(archiveURL: archiveURL, services: services)
            // Update the code
            .flatMap({
                return self.updateFunctionCode($0,
                                               archiveURL: archiveURL,
                                               services: services)
            })
            // Lock the code by publishing a new version
            .flatMap({ self.publishLatest($0, services: services) })
            
            // Make sure that it's still working
            .flatMap({ self.verifyLambda($0, services: services) })
            
            // Update the alias to point to the new revision
            .flatMap({ updateFunctionVersion($0, alias: alias, services: services) })
            
            .map {
                services.logger.info("Done publishing: \(archiveURL.lastPathComponent)")
                return $0
            }
            .flatMapError { (error: Error) -> EventLoopFuture<Lambda.AliasConfiguration> in
                services.logger.info("Error publishing: \(archiveURL.lastPathComponent).\n\(error)")
                return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
            }
    }
    
    public func getFunctionConfiguration(archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        let functionName: String
        do {
            functionName = try functionNameParser(archiveURL)
        } catch {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
        }
        return services.lambda.getFunctionConfiguration(.init(functionName: functionName),
                                                        logger: services.awsLogger)
    }
    
    /// The default format for an archive is function_yyyymmdd_HHMM.zip
    /// If your archive names are in a different format you can override this parser with a custom function
    /// to handle parsing the function name a different way.
    public var functionNameParser: (URL) throws -> String = Self.parseFunctionName
    /// Parses the Lambda function name out of the archive naem.
    /// - Parameter archiveURL: Path to the archive to parse the filename of. The filename must be in the format function_yyyymmdd_HHMM
    /// - Returns: Function name prefix of an archive.
    public static func parseFunctionName(from archiveURL: URL) throws -> String {
        // Given a name like my-function_yyyymmdd_HHMM.zip
        let components = archiveURL.lastPathComponent.components(separatedBy: "_")
        
        guard components.count >= 3 else {
            // At very least there should be the function_date_time.zip
            throw BlueGreenPublisherError.invalidArchiveName(archiveURL.absoluteString)
        }
        // In the case of one or more underscores in the function name, we should return all but the last 2 component since it's the date and time
        return components[0..<components.count-2].joined(separator: "_") // components were joined by dashes we are just dropping the last two.
    }
    
    /// Creates a new Lambda version with the provided archive.
    /// - Returns: FunctionConfiguration of the updated Lambda function
    public func updateFunctionCode(_ configuration: Lambda.FunctionConfiguration,
                                   archiveURL: URL,
                                   services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.info("Update function code")
        guard let data = FileManager.default.contents(atPath: archiveURL.absoluteString),
              data.count > 0
        else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.archiveDoesNotExist(archiveURL.absoluteString))
        }
        guard let functionName = configuration.functionName else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionCode"))
        }
        guard let revisionId = configuration.revisionId else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("revisionId", "updateFunctionCode"))
        }
        
        return services.lambda.updateFunctionCode(.init(functionName: functionName, revisionId: revisionId, zipFile: data),
                                                  logger: services.awsLogger)
    }
    
    public func publishLatest(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.info("Publish $LATEST")
        guard let functionName = configuration.functionName else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "publishLatest"))
        }
        guard let codeSha256 = configuration.codeSha256 else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("codeSha256", "publishLatest"))
        }
        services.logger.info("Publishing $LATEST: \(functionName)")
        return services.lambda.publishVersion(.init(codeSha256: codeSha256, functionName: functionName),
                                              logger: services.awsLogger)
    }
    
    /// Verifies that the Lambda doesn't have any startup errors. Currently we assume that all Lambda functions use
    /// JWT messages in the body of an APIGateway.V2.Request. Once the OmniHandler is working we can simply invoke
    /// the function.
    /// - Parameter configuration: FunctionConfiguration result from calling `updateFunctionCode`
    /// - Throws: Errors if the Lambda had issues being invoked
    /// - Returns: codeSha256 for success, throws if errors are encountered
    public func verifyLambda(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.info("Verify Lambda")
        guard let functionName = configuration.functionName else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "verifyLambda"))
        }
        guard let version = configuration.version else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("version", "verifyLambda"))
        }
        
        
        // TODO: Maybe we can pass in some expected input?
        // The payload doesn't matter, a different kind of error will be returned
        let functionVersion = "\(functionName):\(version)"
        let payload = APIGateway.V2.Request.wrapRawBody(url: URL(string: "https://verify.lambda")!, httpMethod: .POST, body: "")
        services.logger.info("Verifying Lambda: \(functionVersion). Payload: \(String(data: payload, encoding: .utf8)!)")
        let action: () -> EventLoopFuture<Lambda.FunctionConfiguration> = {
            services.lambda.invoke(.init(functionName: functionVersion, payload: .data(payload)), logger: services.awsLogger)
                .flatMapThrowing({ (response: Lambda.InvocationResponse) -> Lambda.FunctionConfiguration in
                    // Throw if there was an error executing the funcion
                    if let _ = response.functionError,
                       let message = response.payload?.asString() {
                        throw BlueGreenPublisherError.invokeLambdaFailed(functionName, message)
                    }
                    return configuration
                })
        }
        // Delay the execution for a second while AWS wraps up
        return services.lambda.eventLoopGroup.next().flatScheduleTask(in: TimeAmount.milliseconds(250)) { () -> EventLoopFuture<Lambda.FunctionConfiguration> in
            return action()
        }.futureResult
        // TODO: Maybe retry after delay again?
//        .flatMapError({ _ in
//            // retry once
//            return action()
//        })
    }
    public func updateFunctionVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        services.logger.info("Update function version")
        guard let functionName = configuration.functionName else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionVersion"))
        }
        guard let version = configuration.version else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("version", "updateFunctionVersion"))
        }
        
        services.logger.info("Updating \(alias) alias for \(functionName) to version: \(version)")
        return services.lambda.updateAlias(.init(functionName: functionName,
                                                 functionVersion: version,
                                                 name: alias),
                                           logger: services.awsLogger)
    }
}
