## AWSDeployKit

[<img src="http://img.shields.io/badge/swift-5.3-brightgreen.svg" alt="Swift 5.3" />](https://swift.org)
[<img src="https://github.com/saltzmanjoelh/AWSDeployKit/workflows/Swift/badge.svg" />](https://github.com/saltzmanjoelh/AWSDeployKit/actions)
[<img src="https://codecov.io/gh/saltzmanjoelh/AWSDeployKit/branch/main/graph/badge.svg" alt="Codecov Result" />](https://codecov.io/gh/saltzmanjoelh/AWSDeployKit)

Helps with building Swift packages in Linux and updating an existing AWS Lambda. 

The `AWSDeploy` product is simply an executable target for the `AppDeployer`. If you plan on [using this from the command line](#using-from-the-command-line), you will simply build the aws-deploy target and copy the product somewhere. However, I prefer to [use this in Xcode](#use-this-in-xcode).

## How does it work?

### Pick a path
In it's simpliest form, you execute the `aws-deploy` binary and it will use your current working directory. You can override this and specify which directory with `-d path-to-package` or `--directoryPath path-to-package`. 

### Build in Docker
It will read your Swift package and from within Docker and build all of the executable targets. You can override this in a couple different ways. Since it will build all executables by default, you can simply provide `-s name-of,targets,to-skip`. Or you can tell it to explicity build only one target by passing the executable target's name, as in:  `aws-deploy example-lambda` .

The Docker image `swift:5.3-amazonlinux2` will be used by default. You can override this by adding a Dockerfile to the root of the package's directory. 

The built products will be available at `./build/lambda/$EXECUTABLE/`. You will also find a zip in there which contains everything that can be uploaded to the AWS Lambda. The archive will be in the format `$EXECUTABLE_ISO8601Date.zip`, where the date is the date when the build occurred.

### Blue/green publish changes
If you pass the `-p` or `--publishBlueGreen` flag, it will publish the changes to a Lambda function. By default, we assume that the Lambda function name matches the executable's name which will also be the prefix of the archive's filename `$EXECUTABLE_ISO8601Date.zip`. So, you have an executable target in your Swift package called `example-lambda`, the archive will be named `example-lambda_ISO8601Date.zip` and the matching Lamba should be named `example-lambda`. We assume that the Lambda has already been setup. This will simply handle the updates.

The blue/green deployment steps are as follows:
* Update the Lambda function code. [UpdateFunctionCode](https://docs.aws.amazon.com/lambda/latest/dg/API_UpdateFunctionCode.html)
* Publish the updated code to $LATEST so that a new version number is created. [PublishVersion](https://docs.aws.amazon.com/lambda/latest/dg/API_PublishVersion.html)
* Verify that the function does not have startup errors. [Invoke](https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html)
* Point the Lambda's `production` alias to the new version. [UpdateAlias](https://docs.aws.amazon.com/lambda/latest/dg/API_UpdateAlias.html)

## Using in Xcode
You are basically duplicating the `aws-deploy` target.

* Create a new target that depends on `AWSDeployCore`. Let's call this `Deploy` for the example.
```swift
.target(
    name: "Deploy",
    dependencies: [
        .product(name: "AWSDeployCore", package: "AWSDeployKit")
    ]),
```

* You only need 2 lines in the `main.swift` file:
  ```swift
  import AWSDeployCore
  AppDeployer.main()
  ```
  
* Switch your selected target in Xcode to your new target `Deploy`.
* Press `cmd` + `shift` + `<` to edit the scheme.
* Add the path to your project in the "Arguments Passed On Launch" section `-d /path/to/project/`.
* Make sure to skip the building and deploying your `Deploy` executable `-s Deploy`.
* This is enough to build in Docker. You can optionally pass the `-p` to publish to your Lambda.
![Example Setup](ExampleSetup.png)

Now when you want to deploy, simply pick your new target and run. Logs should appear in the Xcode console. 

You can take a look at the [AWSDeployKitExample](https://github.com/saltzmanjoelh/AWSDeployKitExample) project as well.



## Using from the command line

* Build the `aws-deploy` target.
* Copy to `/usr/local/bin` or similar.
* Run it with the path to your project directory. `aws-deploy -d /path/to/project`.


TODO:
* Ask to create the Lambda if it doesn't exist.
* Allow executing a custom command like `aws sam-deploy`
* Add a readme for the cli args
