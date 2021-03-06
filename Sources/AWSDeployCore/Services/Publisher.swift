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

public protocol BlueGreenPublisher {
    var functionRole: String? { get set }

    func publishArchive(_ archiveURL: URL,
                        from packageDirectory: URL,
                        invocationTask: InvocationTask?,
                        alias: String,
                        services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    
    func createRole(_ roleName: String, services: Servicable) -> EventLoopFuture<String>
    func createLambda(with archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func createFunctionCode(archiveURL: URL, role: String, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func getFunctionConfiguration(for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func getRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String>
    func generateRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String>
    func handlePublishingError(_ error: Error, for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func parseFunctionName(from archiveURL: URL, services: Servicable) -> EventLoopFuture<String>
    func publishFunctionCode(_ archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func publishLatest(_ configuration: Lambda.FunctionConfiguration, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func publishNewVersion(_ archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func updateFunctionCode(_ configuration: Lambda.FunctionConfiguration, archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
    func updateAliasVersion(_ configuration: Lambda.FunctionConfiguration, alias: String, services: Servicable) -> EventLoopFuture<Lambda.AliasConfiguration>
    func validateRole(_ role: String, services: Servicable) -> EventLoopFuture<String>
    func verifyLambda(_ configuration: Lambda.FunctionConfiguration,
                      invocationTask: InvocationTask?,
                      services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration>
}

// MARK: - Publisher
public struct Publisher: BlueGreenPublisher {
    
    static var basicExecutionRole = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    /// If the Lambda that we are trying to create does not exist already, we create it.
    /// This is the role that we use in it's execution policy.
    public var functionRole: String? = nil
    
    public static var defaultAlias = "development"
    
    public init() {}

    /// Creates a new Lambda function or updates an existing one.
    /// During which, it also invokes the function to make sure that it's not crashing.
    /// Finally, it points the API Gateway to the new Lambda function version.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    ///   - packageDirectory: If the payload is a file path, this is the Swift package that
    ///   - invokePayload: a JSON string or a file apth to a JSON file prefixed with "file://".
    ///   - invocationSetUp: Optionally, before running the `verifyLambda` step you can run some async tasks with this like setting up some existing data in the datastore.
    ///   - verifyResponse: Optionally, add some extra verification for the new response that the updated Lambda is returning.
    ///   - alias: The alias that will point to the updated code.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: The `Lambda.AliasConfiguration` for the updated alias.
    public func publishArchive(_ archiveURL: URL,
                               from packageDirectory: URL,
                               invocationTask: InvocationTask? = nil,
                               alias: String = Self.defaultAlias,
                               services: Servicable = Services.shared) -> EventLoopFuture<Lambda.AliasConfiguration> {
        // Since this is a control function, we use services.publisher instead of self
        // because it gives us a way to use mocks.
        services.logger.trace("--- Publishing: \(archiveURL) ---")
        return publishNewVersion(archiveURL, services: services)
                
            // Make sure that it's working.
            .flatMap { services.publisher.verifyLambda($0,
                                                       invocationTask: invocationTask,
                                                       services: services) }
            
            // Update the alias to point to the new revision.
            .flatMap { services.publisher.updateAliasVersion($0, alias: alias, services: services) }
            
            // Log any final error that might have occurred during the process
            .flatMapError { (error: Error) -> EventLoopFuture<Lambda.AliasConfiguration> in
                services.logger.trace("Error publishing: \(archiveURL.lastPathComponent).\n\(error)")
                return services.lambda.client.eventLoopGroup.next().makeFailedFuture(error)
            }
    }
    
    // Create/Update the source code of the function
    public func publishNewVersion(_ archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        return services.publisher.publishFunctionCode(archiveURL, services: services)
            // Lock the code by publishing a new version.
            .flatMap { services.publisher.publishLatest($0, services: services) }
    }
    
    /// Determines if the Lambda should be created or updated and performs that action.
    /// - Parameters:
    ///   - archiveURL: A URL to the archive which will be used as the function's new code.
    ///   - services: The set of services which will be used to execute your request with.
    /// - Returns: The `Lambda.FunctionConfiguration` for the new/updated function.
    public func publishFunctionCode(_ archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        // Get the name of the function
        return parseFunctionName(from: archiveURL, services: services)
            // Get it's current configuration
            .flatMap({ (functionName: String) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                return services.publisher.getFunctionConfiguration(for: archiveURL, services: services)
            })
            // Update the function
            .flatMap { (configuration: Lambda.FunctionConfiguration) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                return services.publisher.updateFunctionCode(configuration, archiveURL: archiveURL, services: services)
            }
            // If we failed to get the function configuration, we create the function here
            .flatMapError({ (error: Error) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                // If it's "function not found", create the function
                return services.publisher.handlePublishingError(error, for: archiveURL, services: services)
            })
    }
    
}

// MARK: - Update
extension Publisher {
    
    /// Updates an existing Lambda version with the provided archive.
    /// - Parameters:
    ///    - configuration: The current `Lambda.FunctionConfiguration`.
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    ///    - services: The set of services which will be used to execute your request with.
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
        .map {
            services.logger.trace("Done updating Lambda: \(archiveURL.lastPathComponent)")
            return $0
        }
    }
}

// MARK: - Create
extension Publisher {
    
    /// Creates a new Lambda version with the provided archive.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used as the function's new code and name.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns: FunctionConfiguration of the updated Lambda function.
    public func createLambda(with archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        
        return getRoleName(archiveURL: archiveURL, services: services)
            .flatMap({ role in
                services.publisher.validateRole(role, services: services)
            })
            .flatMap({ (role: String) -> EventLoopFuture<Lambda.FunctionConfiguration> in
                services.publisher.createFunctionCode(archiveURL: archiveURL, role: role, services: services)
            })
            .map {
                services.logger.trace("Done creating Lambda: \(archiveURL.lastPathComponent)")
                return $0
            }
    }
    
    /// Creates a new Lambda version with the provided archive.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    ///    - role: The name of the service role used for executing the Lambda
    ///    - services: The set of services which will be used to execute your request with.
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
    
    /// Gets the name of the role used for executing the Lambda. If one was supplied, it is used.
    /// Otherwise, it is generated using the name of the archive.
    /// - Parameters:
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns: The role used to execute the Lambda with.
    public func getRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
        let roleFuture: EventLoopFuture<String>
        if let role = functionRole {
            roleFuture = services.lambda.client.eventLoopGroup.next().makeSucceededFuture(role)
        } else {
            roleFuture = services.publisher.generateRoleName(archiveURL: archiveURL, services: services)
        }
        return roleFuture
    }
    
    /// Uses the supplied functionRole if it's available. Otherwise it creates a unique one.
    /// - Parameters:
    ///    - archiveURL: Path to the archive to parse the filename of if the functionRole is nil. The filename must be in the format `function-name.zip`.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns String that represents the name of the role.
    public func generateRoleName(archiveURL: URL, services: Servicable) -> EventLoopFuture<String> {
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
    
    /// Verifies that the role is in the required aws format.
    /// If it's not in the correct format, we attempt to get the account id and add the correct prefix.
    /// - Parameters:
    ///    - role: The role we are validating
    ///    - services: The set of services which will be used to execute your request with.
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
    /// - Parameters:
    ///    - roleName: The name of the role to create
    ///    - services: The set of services which will be used to execute your request with.
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
                services.iam.attachRolePolicy(.init(policyArn: Publisher.basicExecutionRole,
                                                    roleName: roleName))
            }
            .map({ roleName })
    
    }
    
}

// MARK: - Steps
extension Publisher {
    
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
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    ///    - services: The set of services which will be used to execute your request with.
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
    ///    - services: The set of services which will be used to execute your request with.
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
    ///    - error: The error received when trying to publish the function code
    ///    - archiveURL: A URL to the archive which will be used as the function's new code.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Returns: The error original error, an error from a file attempt of creating the Lambda or the function config from a successful creation.
    public func handlePublishingError(_ error: Error, for archiveURL: URL, services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        // If we get an error that contains "Function not found", create the Lambda
        guard "\(error)".contains("Function not found") else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(error)
        }
        return services.publisher.createLambda(with: archiveURL, services: services)
    }
    /// Verifies that the Lambda doesn't have any startup errors.
    /// - Parameters:
    ///    - configuration: FunctionConfiguration result from calling `updateFunctionCode`.
    ///    - invokePayload: JSON string payload to invoke the Lambda with
    ///    - invocationSetUp: Before invoking the Lambda, you can run some async tasks with this like setting up some existing data in the datastore.
    ///    - verifyAction: When invoking the Lambda, we simply check if an error was returned or not. You can further verify the details of the response with this action.
    ///    - services: The set of services which will be used to execute your request with.
    /// - Throws: Errors if the Lambda had issues being invoked.
    /// - Returns: codeSha256 for success, throws if errors are encountered.
    public func verifyLambda(_ configuration: Lambda.FunctionConfiguration,
                             invocationTask: InvocationTask? = nil,
                             services: Servicable) -> EventLoopFuture<Lambda.FunctionConfiguration> {
        // If an InvocationTask was provided, we test that the Lambda still works. Otherwise, we skip this step
        services.logger.trace("Verify Lambda")
        guard var task = invocationTask else { return services.lambda.eventLoopGroup.next().makeSucceededFuture(configuration) }
        guard let functionName = configuration.functionName else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("functionName", "verifyLambda"))
        }
        guard let version = configuration.version else {
            return services.s3.client.eventLoopGroup.next().makeFailedFuture(BlueGreenPublisherError.invalidFunctionConfiguration("version", "verifyLambda"))
        }

        task.functionName = "\(functionName):\(version)"
        
        return task.run(services: services)
            .map({ _ in configuration })
    }
    
    /// Creates a version from the current code and configuration of a function.
    /// - Parameters:
    ///    - configuration: The current `Lambda.FunctionConfiguration`.
    ///    - services: The set of services which will be used to execute your request with.
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
    ///    - services: The set of services which will be used to execute your request with.
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
