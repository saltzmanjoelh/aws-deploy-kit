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
                                                           abstract: "Invoke your Lambda. This is used in the publishing process to verify that the Lambda is still running properly before the alias is updated.\nYou could also use this when debugging.")
    static let functionHelp = """
    The name of the Lambda function, version, or alias. 
    Name formats: Function name, my-function (name-only), my-function:v1 (with alias).
    Function ARN - arn:aws:lambda:us-west-2:123456789012:function:my-function.
    Partial ARN - 123456789012:function:my-function.
    You can append a version number or alias to any of the formats. The length constraint applies only to the full ARN. If you specify only the function name, it is limited to 64 characters in length.
    
    For invoking multiple functions, simply provide a comma separated list of function names like: `my-function,my-other-function`.
    """
    @Argument(help: ArgumentHelp(
                "\(Self.functionHelp)",
                valueName: "function(s)"))
    var function: String
    
    @OptionGroup
    var payloadsOption: InvokeMultiplePayloadsOption
    
    @OptionGroup
    var options: InvokeOptions
}

struct InvokeOptions: ParsableArguments {
    
    @OptionGroup
    var directory: DirectoryOption
    
    @Option(name: [.short, .long], help: "If you leave this empty, it will use the default AWS URL. You can override this with a local URL for debugging.")
    var endpointURL: String = ""
}

struct InvokeSinglePayloadOption: ParsableArguments {
    static var help = """
    The payload can either be a JSON string or a file path to a JSON file with the "file://" prefix (file://payload.json).
    If you don't provide a payload, an empty string will be sent. Sending an empty string simply checks if the function has any startup errors. It would be more useful if you customize this option with a JSON string that your function can parse and run with.
    """
    @Option(name: [.short, .long], help: "\(help)")
    var payload: String = ""
}
struct InvokeMultiplePayloadsOption: ParsableArguments {
    
    static var help = """
    When invoking multiple functions, you can provide a single value or, you can provide multiple comma separated values. The values can be with JSON strings or file paths like: `file:///path/to/payload1.json,file:///path/to/payload2.json`. If you provide the directory option (`-d` or `--directory`), you can use paths that are relative to each function's source directory. For example, if you include a file with the same name in each executable's source directory, then you can provide a single value for all functions. For example `invoke my-func,my-other-func file://payload.json -d /path/to/project`.
    """
    @Option(name: [.short, .long], help: ArgumentHelp(
                "\(InvokeSinglePayloadOption.help)\n\n\(help)",
                valueName: "payload(s)"))
    var payload: String = ""
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
        let functions = function.components(separatedBy: ",")
        let payloads = payloadsOption.payload.components(separatedBy: ",")
        for i in 0..<functions.count {
            let function = functions[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let payloadIndex = payloads.count == functions.count ? i : 0
            let payload = payloads[payloadIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = try services.invoker.invoke(function: function, with: payload, services: services).wait(),
               let response = String(data: data, encoding: .utf8) {
                services.logger.trace(.init(stringLiteral: "\(response)"))
            } else {
                services.logger.trace("Invoke \(function) completed with no response to print.")
            }
        }
    }
}
