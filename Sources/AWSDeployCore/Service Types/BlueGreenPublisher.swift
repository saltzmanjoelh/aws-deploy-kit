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
import SotoSTS
import SotoIAM

public protocol Publisher {
    var functionRole: String? { get set }
    var alias: String { get set }

    func publishArchive(_ archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    func createRole(_ roleName: String, services: Servicable) -> EventLoopFuture<String>
    func createLambda(with archiveURL: URL, role: String, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    func createFunctionCode(archiveURL: URL, role: String, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func getFunctionConfiguration(for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func getRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String>
    func handlePublishingError(_ error: Error, for archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    func parseFunctionName(from archiveURL: URL, services: Servicable) -> EventLoopFuture<String>
    func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]>
    func publishLatest(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func updateFunctionCode(_ configuration: Lambda.FunctionConfiguration, archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func updateAliasVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    func updateLambda(with archiveURL: URL, configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    func validateRole(_ role: String, services: Servicable) -> EventLoopFuture<String>
    func verifyLambda(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
}

// MARK: - BlueGreenPublisher
public struct BlueGreenPublisher: Publisher {
    
    static var basicExecutionRole = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    /// If the Lambda that we are trying to create does not exist already, we create it.
    /// This is the role that we use in it's execution policy.
    public var functionRole: String? = nil
    
    public static var defaultAlias = "development"
    public var alias: String = Self.defaultAlias
    
    public init() {}

    /// Creates a new Lambda function or updates an existing one.
    /// During which, it also invokes the function to make sure that it's not crashing.
    /// Finally, it points the API Gateway to the new Lambda function version.
    public func publishArchives(_ archiveURLs: [URL], services: Servicable) throws -> EventLoopFuture<[Lambda.AliasConfiguration]> {
        let futures = archiveURLs.map { self.publishArchive($0, alias: services.publisher.alias, services: services) }
        return EventLoopFuture.reduce(
            into: [Lambda.AliasConfiguration](),
            futures,
            on: services.lambda.client.eventLoopGroup.next()
        ) { result, nextValue in
            result.append(nextValue)
            services.logger.trace("Updated: \(nextValue)")
        }
    }

    /// Determines if the Lambda should be created or updated and performs that action.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    ///   - alias: The alias that will point to the updated code.
    /// - Returns: The `Lambda.AliasConfiguration` for the updated alias.
    public func publishArchive(_ archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        // Since this is a control function, we use services.publisher instead of self
        // because it gives us a way to use mocks. Maybe convert to static instead?
        services.logger.trace("--- Publishing: \(archiveURL) ---")
        // Get the name of the function
        return parseFunctionName(from: archiveURL, services: services)
            // Get it's current configuration
            .flatMap({ (functionName: String) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                return services.publisher.getFunctionConfiguration(for: archiveURL, services: services)
            })
            // Update the function
            .flatMap { (configuration: Lambda.FunctionConfiguration) -> EventLoopFuture<Lambda.AliasConfiguration> in
                return services.publisher.updateLambda(with: archiveURL, configuration: configuration, alias: alias, services: services)
            }
            .flatMapError({ (error: Error) -> EventLoopFuture<Lambda.AliasConfiguration> in
                // If it's "function not found", create the function
                return services.publisher.handlePublishingError(error, for: archiveURL, alias: alias, services: services)
            })
            // Log any final error that might have occurred during the process
            .flatMapError { (error: Error) -> EventLoopFuture<Lambda.AliasConfiguration> in
                services.logger.trace("Error publishing: \(archiveURL.lastPathComponent).\n\(error)")
                return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
            }
    }
    
}

// MARK: - Update
extension BlueGreenPublisher {
    /// Publishes a new version of an existig Lambda function by doing the following:
    /// * Update the function's code.
    /// * Lock the new code and give it a new version number.
    /// * Verify that the code starts up by invoking it.
    /// * Updates the supplied alias to point to the new version.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    ///   - alias: The alias that will point to the updated code.
    /// - Returns: The `Lambda.AliasConfiguration` for the updated alias.
    public func updateLambda(with archiveURL: URL,
                             configuration: Lambda.FunctionConfiguration,
                             alias: String,
                             services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        
        // Update the code
        services.publisher.updateFunctionCode(
            configuration,
            archiveURL: archiveURL,
            services: services
        )
        // Lock the code by publishing a new version.
        .flatMap { services.publisher.publishLatest($0, services: services) }

        // Make sure that it's still working.
        .flatMap { services.publisher.verifyLambda($0, services: services) }

        // Update the alias to point to the new revision.
        .flatMap { services.publisher.updateAliasVersion($0, alias: alias, services: services) }

        .map {
            services.logger.trace("Done updating Lambda: \(archiveURL.lastPathComponent)")
            return $0
        }
    }
    
    /// Updates an existing Lambda version with the provided archive.
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
}

// MARK: - Create
extension BlueGreenPublisher {
    
    /// Creates a new Lambda version with the provided archive.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used as the function's new code and name.
    ///    - role: The execution role for the function.
    ///    - alias: The alias that will reference this version of the new function.
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func createLambda(with archiveURL: URL, role: String, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        return services.publisher.createFunctionCode(archiveURL: archiveURL, role: role, services: services)
            // Lock the code by publishing a new version.
            .flatMap { services.publisher.publishLatest($0, services: services) }
            
            // Make sure that it's working.
            .flatMap { services.publisher.verifyLambda($0, services: services) }
            
            // Update the alias to point to the new revision.
            .flatMap { services.publisher.updateAliasVersion($0, alias: alias, services: services) }
            
            .map {
                services.logger.trace("Done creating Lambda: \(archiveURL.lastPathComponent)")
                return $0
            }
    }
    
    /// Creates a new Lambda version with the provided archive.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    ///    - role: The name of the service role used for executing the Lambda
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func createFunctionCode(archiveURL: URL, role: String, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        services.logger.trace("Create function code from: \(archiveURL)")
        guard let data = services.fileManager.contents(atPath: archiveURL.path),
              data.count > 0
        else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.archiveDoesNotExist(archiveURL.path))
        }
        return parseFunctionName(from: archiveURL, services: services)
            .flatMap({ (functionName: String) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                return services.lambda.createFunction(.init(code: .init(zipFile: data),
                                                            functionName: functionName,
                                                            handler: "main", // Doesn't matter in this case
                                                            role: role,
                                                            runtime: Lambda.Runtime.providedAl2),
                                                      logger: services.awsLogger)
                    // Nested in here so that we have access to functionName and don't need to handle
                    // the configuration possibly having a nil functionName. Unlikey in production
                    // but possible when testing and returning our own responses for the mock server.
                    .flatMap { (configuration: Lambda.FunctionConfiguration) in
                        // Create the default "development" alias
                        services.lambda.createAlias(.init(functionName: functionName,
                                                          functionVersion: configuration.version ?? "1",
                                                          name: Self.defaultAlias))
                            .map({ _ in configuration })
                    }
            })
    }
    
    /// Uses the supplied functionRole if it's available. Otherwise it creates a unique one.
    /// - Parameter archiveURL: Path to the archive to parse the filename of if the functionRole is nil. The filename must be in the format `function-name.zip`.
    /// - Returns String that represents the name of the role.
    public func getRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        guard let role = functionRole else {
            return parseFunctionName(from: archiveURL, services: services)
                // Generate our own
                .map({ (functionName: String) -> String in
                    return "\(functionName)-role-\(UUID().uuidString.suffix(8))"
                })
                // We generated a role name, create it in AWS
                .flatMap({ (role: String) -> EventLoopFuture<String> in
                    return services.publisher.createRole(role, services: services)
                })
        }
        return services.lambda.client.eventLoopGroup.next().makeSucceededFuture(role)
    }
    
    /// Verifies that the role is in the required aws format.
    /// If it's not in the correct format, we attempt to get the account id and add the correct prefix.
    /// - Parameter role: The role we are validating
    /// - Returns A role with the arn:aws:iam::ACCOUNT_ID:role/ prefix
    public func validateRole(_ role: String, services: Servicable) -> EventLoopFuture<String> {
        guard !role.hasPrefix("arn:") else {
            return services.lambda.client.eventLoopGroup.next().makeSucceededFuture(role)
        }
        return services.sts.getCallerIdentity(.init())
            .flatMapThrowing { (response: STS.GetCallerIdentityResponse) -> String in
                guard let accountId = response.account else {
                    throw BlueGreenPublisherError.accountIdUnavailable
                }
                return "arn:aws:iam::\(accountId):role/\(role)"
            }
    }
    
    /// Creates the provided role.
    /// - Parameter roleName: The name of the role to create
    /// - Returns String that represents the name of the role that was created.
    public func createRole(_ roleName: String, services: Servicable) -> EventLoopFuture<String> {
        // Create the role with a policy document
        let policy = "{\"Version\": \"2012-10-17\",\"Statement\": [{ \"Effect\": \"Allow\", \"Principal\": {\"Service\": \"lambda.amazonaws.com\"}, \"Action\": \"sts:AssumeRole\"}]}"
        return services.iam.createRole(.init(assumeRolePolicyDocument: policy, roleName: roleName))
            .flatMapThrowing({ (response: IAM.CreateRoleResponse) in
                // Make sure that the roleName we received is the same
                // as the one we requested.
                guard response.role.roleName == roleName else {
                    throw BlueGreenPublisherError.invalidCreateRoleResponse(roleName, response.role.roleName)
                }
                return response.role.roleName
            })
            .flatMap { (roleName: String) -> EventLoopFuture<Void> in
                // Attaches the AWSLambdaBasicExecutionRole
                services.iam.attachRolePolicy(.init(policyArn: BlueGreenPublisher.basicExecutionRole,
                                                    roleName: roleName))
            }
            .map({ roleName })
    
    }
    
}

// MARK: - Steps
extension BlueGreenPublisher {
    
    /// Parses the Lambda function name out of the archive name.
    /// - Parameter archiveURL: Path to the archive to parse the filename of. The filename must be in the format `function-name.zip`
    /// - Returns: Function name prefix of an archive.
    public static func parseFunctionName(from archiveURL: URL) throws -> String {
        // Given a name like my-function.zip
        let functionName = archiveURL.lastPathComponent.replacingOccurrences(of: ".zip", with: "")

        guard functionName.count > 0 else {
            // At very least there should be the function_name.zip
            throw BlueGreenPublisherError.invalidArchiveName(archiveURL.path)
        }
        return functionName
    }

    /// Uses `Lambda.getFunctionConfiguration` to get the functions current configuration.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func parseFunctionName(from archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        do {
            let functionName = try Self.parseFunctionName(from: archiveURL)
            return services.lambda.client.eventLoopGroup.next().makeSucceededFuture(functionName)
        } catch {
            return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
        }
    }
    
    /// Parses the function name from an archive and tries to get the related Lambda configuration.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used to parse the function name from.
    /// - Returns: The error original error, an error from a file attempt of creating the Lambda or the alias config from a successful creation.
    public func getFunctionConfiguration(for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        parseFunctionName(from: archiveURL, services: services)
            .flatMap({ (functionName: String) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                services.lambda.getFunctionConfiguration(.init(functionName: functionName), logger: services.awsLogger)
            })
    }
    
    /// When publishing the first step is to get the function's configuration. If an error is returned, we handle it here.
    /// If the error is "Function not found", we try to create the Lambda function.
    /// Otherwise, we just forward the error along.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    /// - Returns: The error original error, an error from a file attempt of creating the Lambda or the alias config from a successful creation.
    public func handlePublishingError(_ error: Error, for archiveURL: URL, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
        // If we get an error that contains "Function not found", create the Lambda
        guard "\(error)".contains("Function not found") else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(error)
        }
        return services.publisher.getRoleName(archiveURL: archiveURL, services: services)
            .flatMap({ role in
                services.publisher.validateRole(role, services: services)
            })
            .flatMap({ (role: String) -> EventLoopFuture<Lambda.AliasConfiguration> in
                services.publisher.createLambda(with: archiveURL, role: role, alias: alias, services: services)
            })
    }
    /// Verifies that the Lambda doesn't have any startup errors.
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

        let functionVersion = "\(functionName):\(version)"
        
        // Delay the execution for a second while AWS wraps up.
        return services.lambda.eventLoopGroup.next().flatScheduleTask(in: TimeAmount.milliseconds(250)) { () -> EventLoopFuture<Lambda.FunctionConfiguration> in
            services.invoker.invoke(function: functionVersion, with: "", services: services)
                .map({ _ in configuration })
        }.futureResult
        // TODO: Maybe retry after delay again?
//        .flatMapError({ _ in
//            // retry once
//            return action()
//        })
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
        ).map({ config in
            services.logger.trace("New version: \(config.version ?? "No Version Specified")")
            return config
        })
    }
    
    /// Updates the supplied alias to point to a different version number.
    /// - Parameters:
    ///    - configuration: The `Lambda.FunctionConfiguration` to get the version number from.
    ///    - alias: The alias you want to update.
    /// - Returns: The updated `Lambda.AliasConfiguration`.
    public func updateAliasVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration> {
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
