//
//  InvokeCommand.swift
//  
//
//  Created by Joel Saltzman on 6/19/21.
//

import Foundation
import ArgumentParser
import SotoLambda

struct InvokeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "invoke",
                                                           abstract: "Invoke your Lambda. This is used in the publishing process to verify that the Lambda is still running properly before the alias is updated.\nYou could also use this when debugging")
    
    @Argument(help: "The name of the Lambda function, version, or alias.  Name formats: Function name, my-function (name-only), my-function:v1 (with alias).\nFunction ARN - arn:aws:lambda:us-west-2:123456789012:function:my-function.\nPartial ARN - 123456789012:function:my-function.\nYou can append a version number or alias to any of the formats. The length constraint applies only to the full ARN. If you specify only the function name, it is limited to 64 characters in length.")
    var function: String
    
    static var payloadHelp = "If you don't provide a payload, an empty string will be sent. Sending an empty string simply checks if the function has any startup errors. It would be more useful if you customize this option with a JSON string that your function can parse and run with. You can provide the JSON string directly. Or if you prefix the string with \"file://\" followed by a path to a file that contains JSON, it will parse the file and use it's contents."
    @Argument(help: "\(Self.payloadHelp)")
    var payload: String = ""
    
    @OptionGroup
    var options: InvokeOptions
}

struct InvokeOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "If you leave this empty, it will use the default AWS URL. You can override this with a local URL for debugging.")
    var endpointURL: String = ""
}


extension InvokeCommand {
    public mutating func run() throws {
        if options.endpointURL.count > 0 {
            Services.shared.lambda = Lambda(client: Services.shared.lambda.client,
                                            region: Services.shared.lambda.region,
                                            endpoint: options.endpointURL)
        }
        try self.run(services: Services.shared)
    }

    public mutating func run(services: Servicable) throws {
        if let data = try services.invoker.invoke(function: function, with: payload, services: services).wait(),
           let response = String(data: data, encoding: .utf8) {
            services.logger.trace(.init(stringLiteral: "\(response)"))
        } else {
            services.logger.trace("Invoke completed with no response to print.")
        }
    }
}
