//
//  File.swift
//  
//
//  Created by Joel Saltzman on 6/19/21.
//

import Foundation
import ArgumentParser
import Logging
import LogKit
import SotoLambda
import SotoS3

struct BuildCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "build",
                                                           abstract: "Build one or more executables inside of a Docker container. It will read your Swift package and build the executables of your choosing. If you leave the defaults, it will build all of the executables in the package. You can optionally choose to skip targets, or you can tell it to build only specific targets.\n\nThe Docker image `swift:5.3-amazonlinux2` will be used by default. You can override this by adding a Dockerfile to the root of the package's directory.\n\nThe built products will be available at `./build/lambda/$EXECUTABLE/`. You will also find a zip in there which contains everything needed to update AWS Lambda code. The archive will be in the format `$EXECUTABLE_NAME.zip`.\n")
    
    @OptionGroup
    var options: BuildOptions
}

struct BuildOptions: ParsableArguments {
    @OptionGroup
    var directory: DirectoryOption
    
    @Argument(help: "You can either specify which products you want to include, or if you don't specify any products, all will be used.")
    var products: [String] = []
    
    @Option(name: [.short, .long], help: "By default if you don't specify any products to build, all executable targets will be built. This allows you to skip specific products. Use a comma separted string. Example: -s SkipThis,SkipThat. If you specified one or more targets, this option is not applicable.")
    var skipProducts: String = ""
    
    @Option(name: [.customShort("e"), .long],
            help: "Run a custom shell command before the build phase. The command will be executed in the same source directory as the product(s) that you specify. If you don't specify any products and all products are built, then this command will be ran with each product in their source directory.")
    var preBuildCommand: String = ""
    
    @Option(name: [.customShort("o"), .long],
            help: "Run a custom shell command like \"aws sam-deploy\" after the build phase. The command will be executed in the same source directory as the product(s) that you specify. If you don't specify any products and all products are built, then this command will be ran after each product is built, in their source directory.")
    var postBuildCommand: String = ""
    
    @Option(name: [.customShort("k"), .long],
    help: "Specify an SSH key for private repos. Since we are building inside Docker, your usual .ssh directory is not available inside the container. Example: -k /home/user/.ssh/my_key")
    var sshKeyPath: String?
}

extension BuildCommand {
    public mutating func run() throws {
        Services.shared.builder.preBuildCommand = options.preBuildCommand
        Services.shared.builder.postBuildCommand = options.postBuildCommand
        _ = try self.run(services: Services.shared)
    }
    
    public mutating func run(services: Servicable) throws -> [URL] {
        let packageDirectory = URL(fileURLWithPath: options.directory.path)
        let sshPrivateKey: URL?
        if let keyPath = options.sshKeyPath,
           services.fileManager.fileExists(atPath: keyPath){
            sshPrivateKey = URL(fileURLWithPath: keyPath)
        } else {
            sshPrivateKey = nil
        }
        return try services.builder.buildProducts(options.products,
                                                  at: packageDirectory,
                                                  skipProducts: options.skipProducts,
                                                  sshPrivateKeyPath: sshPrivateKey,
                                                  services: services)
    }
}
