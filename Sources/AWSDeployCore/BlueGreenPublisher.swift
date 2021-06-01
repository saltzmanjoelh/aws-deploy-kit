//
//  BlueGreenPublisher.swift
//
//
//  Created by Joel Saltzman on 3/25/21.
//

import AWSLambdaEvents
import Foundation
import Logging
import LogKit
import NIO
import SotoLambda
import SotoS3

public struct BlueGreenPublisher {
    public init() {}

    /// Creates a new Lambda function. Then, invokes the function to make sure that it's not crashing.
    /// Finally, it points the API Gateway to the new Lambda function.
    public func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        let futures = archiveURLs.map { self.publishArchive($0, services: services) }
        return EventLoopFuture.reduce(
            into: [Lambda.AliasConfiguration](),
            futures,
            on: services.lambda.client.eventLoopGroup.next()
        ) { result, nextValue in
            result.append(nextValue)
            services.logger.trace("Updated: \(nextValue)")
        }
    }

    /// Publishes a new version of the Lambda function by doing the following:
    /// * Update the function's code.
    /// * Lock the new code and give it a new version number.
    /// * Verify that the code starts up by invoking it.
    /// * Updates the supplied alias to point to the new version.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    ///   - alias: The alias that will point to the updated code.
    /// - Returns: The `Lambda.AliasConfiguration` for the updated alias.
    public func publishArchive(_ archiveURL: URL, alias: String = "production", services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        services.logger.trace("Publishing: \(archiveURL.lastPathComponent)")
        return self.getFunctionConfiguration(archiveURL: archiveURL, services: services)
            // Update the code
            .flatMap {
                self.updateFunctionCode(
                    $0,
                    archiveURL: archiveURL,
                    services: services
                )
            }
            // Lock the code by publishing a new version.
            .flatMap { self.publishLatest($0, services: services) }

            // Make sure that it's still working.
            .flatMap { self.verifyLambda($0, services: services) }

            // Update the alias to point to the new revision.
            .flatMap { updateFunctionVersion($0, alias: alias, services: services) }

            .map {
                services.logger.trace("Done publishing: \(archiveURL.lastPathComponent)")
                return $0
            }
            .flatMapError { (error: Error) -> EventLoopFuture<Lambda.AliasConfiguration> in
                services.logger.trace("Error publishing: \(archiveURL.lastPathComponent).\n\(error)")
                return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
            }
    }

    /// Uses `Lambda.getFunctionConfiguration` to get the functions current configuration.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func getFunctionConfiguration(archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        let functionName: String
        do {
            functionName = try self.functionNameParser(archiveURL)
        } catch {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
        }
        return services.lambda.getFunctionConfiguration(
            .init(functionName: functionName),
            logger: services.awsLogger
        )
    }

    /// The default format for an archive is function_ISO8601Date.zip.
    /// If your archive names are in a different format you can override this parser with a custom function
    /// to handle parsing the function name a different way.
    public var functionNameParser: (URL) throws -> String = Self.parseFunctionName
    
    /// Parses the Lambda function name out of the archive naem.
    /// - Parameter archiveURL: Path to the archive to parse the filename of. The filename must be in the format function_ISO8601Date
    /// - Returns: Function name prefix of an archive.
    public static func parseFunctionName(from archiveURL: URL) throws -> String {
        // Given a name like my-function_ISO8601Date.zip
        var components = archiveURL.lastPathComponent.components(separatedBy: "_")

        guard components.count >= 2 else {
            // At very least there should be the function_ISO8601Date.zip
            throw BlueGreenPublisherError.invalidArchiveName(archiveURL.path)
        }
        // In the case of one or more underscores in the function name, we should return all but the last 1 component since it's the date and time.
        components.removeLast()
        return components.joined(separator: "_") // components were joined by dashes we are just dropping the last two.
    }

    /// Creates a new Lambda version with the provided archive.
    /// - Parameters:
    ///    - configuration: The current `Lambda.FunctionConfiguration`.
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func updateFunctionCode(
        _ configuration: Lambda.FunctionConfiguration,
        archiveURL: URL,
        services: Servicable
    ) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.trace("Update function code")
        guard let data = services.fileManager.contents(atPath: archiveURL.path),
              data.count > 0
        else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.archiveDoesNotExist(archiveURL.path))
        }
        guard let functionName = configuration.functionName else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionCode"))
        }
        guard let revisionId = configuration.revisionId else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("revisionId", "updateFunctionCode"))
        }

        return services.lambda.updateFunctionCode(
            .init(functionName: functionName, revisionId: revisionId, zipFile: data),
            logger: services.awsLogger
        )
    }

    /// Creates a version from the current code and configuration of a function.
    /// - Parameters:
    ///    - configuration: The current `Lambda.FunctionConfiguration`.
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func publishLatest(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.trace("Publish $LATEST")
        guard let functionName = configuration.functionName else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "publishLatest"))
        }
        guard let codeSha256 = configuration.codeSha256 else {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("codeSha256", "publishLatest"))
        }
        services.logger.trace("Publishing $LATEST: \(functionName)")
        return services.lambda.publishVersion(
            .init(codeSha256: codeSha256, functionName: functionName),
            logger: services.awsLogger
        )
    }

    /// Verifies that the Lambda doesn't have any startup errors. Currently we assume that all Lambda functions use
    /// JWT messages in the body of an APIGateway.V2.Request. Once the OmniHandler is working we can simply invoke
    /// the function.
    /// - Parameters:
    ///    - configuration: FunctionConfiguration result from calling `updateFunctionCode`.
    /// - Throws: Errors if the Lambda had issues being invoked.
    /// - Returns: codeSha256 for success, throws if errors are encountered.
    public func verifyLambda(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.trace("Verify Lambda")
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
        services.logger.trace("Verifying Lambda: \(functionVersion). Payload: \(String(data: payload, encoding: .utf8)!)")
        
        let action: () -> EventLoopFuture<Lambda.FunctionConfiguration> = {
            services.lambda.invoke(.init(functionName: functionVersion, payload: .data(payload)), logger: services.awsLogger)
                .flatMapThrowing { (response: Lambda.InvocationResponse) -> Lambda.FunctionConfiguration in
                    // Throw if there was an error executing the funcion
                    if let _ = response.functionError,
                       let message = response.payload?.asString()
                    {
                        throw BlueGreenPublisherError.invokeLambdaFailed(functionName, message)
                    }
                    return configuration
                }
        }
        
        // Delay the execution for a second while AWS wraps up.
        return services.lambda.eventLoopGroup.next().flatScheduleTask(in: TimeAmount.milliseconds(250)) { () -> EventLoopFuture<Lambda.FunctionConfiguration> in
            action()
        }.futureResult
        // TODO: Maybe retry after delay again?
//        .flatMapError({ _ in
//            // retry once
//            return action()
//        })
    }

    /// Updates the supplied alias to point to a different version number.
    /// - Parameters:
    ///    - configuration: The `Lambda.FunctionConfiguration` to get the version number from.
    ///    - alias: The alias you want to update.
    /// - Returns: The updated `Lambda.AliasConfiguration`.
    public func updateFunctionVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        services.logger.trace("Update function version")
        guard let functionName = configuration.functionName else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "updateFunctionVersion"))
        }
        guard let version = configuration.version else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("version", "updateFunctionVersion"))
        }

        services.logger.trace("Updating \(alias) alias for \(functionName) to version: \(version)")
        return services.lambda.updateAlias(
            .init(
                functionName: functionName,
                functionVersion: version,
                name: alias
            ),
            logger: services.awsLogger
        )
    }
}
