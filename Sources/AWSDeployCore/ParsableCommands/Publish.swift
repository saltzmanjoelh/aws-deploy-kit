//
//  Publish.swift
//  
//
//  Created by Joel Saltzman on 6/19/21.
//

import Foundation
import ArgumentParser

extension AWSDeploy {
    struct Publish: ParsableCommand {
        public static let configuration = CommandConfiguration(abstract: "Publish the changes to a Lambda function using a blue green process.\n\nIf there is no existing Lambda with a matching function name, this will create it for you. A role will also be created with AWSLambdaBasicExecutionRole access and assigned to the new Lambda.\n\nIf the Lambda already exists, it's code will simply be updated.\n\nWe test that the Lambda doesn't have any startup errors by using the Invoke API, please check the `aws-deploy invoke --help` for reference. If invoking the function does not abort abnormally, the supplied alias (the default is `development`) will be updated to point to the new version of the Lambda.\n")
        
        // Everything shares the -d, --directory-path option to specify the Swift package directory
        @OptionGroup
        var directory: DirectoryOption
    }
}

struct PublishOptions: ParsableArguments {
    
    @Option(name: [.short, .long],
            help: "When publishing, if you need to create the function, this is the role being used to execute the function. If this is a new role, it will use the arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole policy. This policy can execute the Lambda and upload logs to Amazon CloudWatch Logs (logs::CreateLogGroup, logs::CreateLogStream and logs::PutLogEvents). If you don't provide a value for this the default will be used in the format $FUNCTION-role-$RANDOM.",
            transform: { return $0 })
    var functionRole: String? = nil
    
    @Option(name: [.short, .long], help: "When publishing, this is the alias which will be updated to point to the new release.")
    var alias: String = BlueGreenPublisher.defaultAlias
}
