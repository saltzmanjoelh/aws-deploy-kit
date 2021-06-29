## AWSDeployKit

[<img src="http://img.shields.io/badge/swift-5.3-brightgreen.svg" alt="Swift 5.3" />](https://swift.org)
[<img src="https://github.com/saltzmanjoelh/AWSDeployKit/workflows/Swift/badge.svg" />](https://github.com/saltzmanjoelh/AWSDeployKit/actions)
[<img src="https://codecov.io/gh/saltzmanjoelh/AWSDeployKit/branch/main/graph/badge.svg" alt="Codecov Result" />](https://codecov.io/gh/saltzmanjoelh/AWSDeployKit)

Helps with building Swift packages in Linux and publishing to an AWS Lambda. 

## TLDR
If you plan on [using this from the command line](#using-from-the-command-line), you will simply build the aws-deploy target and copy the product to somewhere. However, I prefer to use this in Xcode, more on this [below](#use-this-in-xcode)

```shell
git clone https://github.com/saltzmanjoelh/aws-deploy-kit.git && \
cd aws-deploy-kit && \
swift build && \
swift run aws-deploy build-and-publish -d /path/to/project aws-lambda-function-name
```

## [Commands](cli-help/)
### [Build](cli-help/02-build.md)
Build one or more executables inside of a Docker container. 

It will read your Swift package and build the executables of your choosing. If you leave the defaults, it will build all of the executables in the package. You can optionally choose to skip targets, or you can tell it to build only specific targets.

It will use your current working directory. You can override this and specify which directory with `-d path-to-package` or `--directoryPath path-to-package`. 

The Docker image `swift:5.3-amazonlinux2` will be used by default. You can override this by adding a Dockerfile to the root of the package's directory. 

The built products will be available at `./build/lambda/$EXECUTABLE_NAME/`. You will also find a zip in there which contains everything needed to update AWS Lambda code. The archive will be in the format `$EXECUTABLE_NAME.zip`.

Please see the [aws-deploy build --help](cli-help/02-build.md) for a complete reference on this command.

### [Publish](cli-help/03-publish.md)
Publish the changes to a Lambda function using a blue green process.

If there is no existing Lambda with a matching function name, this will create it for you. A role will also be created with AWSLambdaBasicExecutionRole access and assigned to the new Lambda.

If the Lambda already exists, it's code will simply be updated.

We test that the Lambda doesn't have any startup errors by using the Invoke API, please check the [aws-deploy invoke --help](cli-help/04-invoke.md) for reference. If invoking the function does not abort abnormally, the supplied alias (the default is `development`) will be updated to point to the new version of the Lambda.

The blue/green deployment steps are as follows:
* Create/update the Lambda function code. [CreateFunction](https://docs.aws.amazon.com/lambda/latest/dg/API_CreateFunction.html) / [UpdateFunctionCode](https://docs.aws.amazon.com/lambda/latest/dg/API_UpdateFunctionCode.html)
* Publish the updated code to $LATEST so that a new version number is created. [PublishVersion](https://docs.aws.amazon.com/lambda/latest/dg/API_PublishVersion.html)
* Verify that the function does not have startup errors. [Invoke](https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html)
* Point the Lambda's alias (default is `development`)  to the new version. [UpdateAlias](https://docs.aws.amazon.com/lambda/latest/dg/API_UpdateAlias.html)

### Invoke

Invoke your Lambda. This is used in the publishing process to verify that the Lambda is still running properly before the alias is updated. You could also use this when debugging. Please read the `aws-deploy invoke help` for more details.

## Using in Xcode
The goal here is to be able to deploy your Lambda functions from within the project that you are working with. You will simply switch your run target to the deployment target and publish a new version of your Lambda. The steps will basically be duplicating the `aws-deploy` target from `aws-deploy-kit`.

From your project that uses `swift-aws-lambda-runtime`, add `aws-deploy-kit` as a dependency.
```swift
dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .branch("main")),
        .package(url: "https://github.com/saltzmanjoelh/aws-deploy-kit", .branch("main")),
    ],
```

Create a new target. Let's call this new target `Deploy` for the example.
```swift
.target(
    name: "Deploy",
    dependencies: [
        .product(name: "AWSDeployCore", package: "aws-deploy-kit")
    ]),
```

`aws-deploy-kit` requires at least macOS 10.12. Make sure to add this to the package manifest

```swift
platforms: [
    .macOS(.v10_12)
],
```

You only need 2 lines in the `main.swift` file:
  ```swift
  import AWSDeployCore
  AWSDeploy.main()
  ```
  
* Switch your selected target in Xcode to your new target `Deploy`.
* Press `cmd` + `shift` + `<` to edit the scheme.
* Add the `build-and-publish` command in the "Arguments Passed On Launch" section
* Add the path to your project in the "Arguments Passed On Launch" section `-d /path/to/project/`.
* This is enough to build in Docker and publish to an AWS Lambda
![Example Setup](ExampleSetup.png)

Now when you want to deploy, simply pick your new target and run. Logs should appear in the Xcode console. 

You can take a look at the [AWSDeployKitExample](https://github.com/saltzmanjoelh/AWSDeployKitExample) project as well.


## Using from the command line

* Build the `aws-deploy` target.
* Copy to `/usr/local/bin` or similar.
* Run it with the path to your project directory. `aws-deploy build-and-publish -d /path/to/project executable-name -p`.
