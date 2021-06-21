//
//  Invoke.swift
//  
//
//  Created by Joel Saltzman on 6/19/21.
//

import Foundation
import ArgumentParser

extension AWSDeploy {
    struct Invoke: ParsableCommand {
        public static let configuration = CommandConfiguration(abstract: "Invoke your Lambda. This is used in the publishing process to verify that the Lambda is still running properly before the alias is updated.\nYou could also use this when debugging")
        
        // Everything shares the -d, --directory-path option to specify the Swift package directory
        @OptionGroup
        var directory: DirectoryOption
    }
}

struct InvokeOptions: ParsableArguments {
    
    @Option(name: [.customShort("i"), .long], help: "If you don't provide a payload, an empty String will be sent. Sending an empty String simply checks if the function has any startup errors. It would be more useful if you customize this option with a JSON String that your function can parse and run with. You ")
    var invokePayload: String = ""
    
    @Option(name: [.short, .long], help: "If you leave this empty, it will use the default AWS URL. You can override this with a local URL for debugging.")
    var endpointURL: String = ""
}
