//
//  AppDeployer.swift
//
//
//  Created by Joel Saltzman on 1/28/21.
//

import ArgumentParser
import Foundation

public struct AWSDeploy: ParsableCommand {
    public static let configuration = CommandConfiguration(abstract: "Helps with building Swift packages in Linux and deploying to Lambda. Currently, we only support building executable targets.\n\nDocker is used for building and packaging. You can use a custom Dockerfile in the root of the Package directory to customize the build container that is used. Otherwise, \(Docker.Config.imageName) will be used by default.\n\nOnce built and packaged, you should find the binary and it's shared libraries in .build/.lambda/$executableName/. You will also find a zip with all those files in that directory as well. Please take a look at the README for more details.",
                                                           subcommands: [Build.self, Publish.self, Invoke.self],
                                                           defaultSubcommand: Build.self)
    
    public init() {}

}

struct DirectoryOption: ParsableArguments {
    @Option(name: [.customShort("d"), .customLong("directory")], help: "Provide a custom path to the project directory instead of using the current working directory.")
    var path: String = "./"
}
