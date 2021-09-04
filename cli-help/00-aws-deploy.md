```swift
OVERVIEW: Helps with building Swift packages in Linux and deploying to Lambda.
Currently, we only support building executable targets.

Docker is used for building and packaging. You can use a custom Dockerfile in
the root of the Package directory to customize the build container that is
used. Otherwise, swift:5.5-amazonlinux2 will be used by default.

Once built and packaged, you should find the binary and it's shared libraries
in .build/.lambda/$executableName/. You will also find a zip with all those
files in that directory as well. Please take a look at the README for more
details.

USAGE: aws-deploy <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  build                   Build one or more executables inside of a Docker
                          container. It will read your Swift package and build
                          the executables of your choosing. If you leave the
                          defaults, it will build all of the executables in the
                          package. You can optionally choose to skip targets,
                          or you can tell it to build only specific targets.

                          The Docker image `swift:5.3-amazonlinux2` will be
                          used by default. You can override this by adding a
                          Dockerfile to the root of the package's directory.

                          The built products will be available at
                          `./build/lambda/$EXECUTABLE/`. You will also find a
                          zip in there which contains everything needed to
                          update AWS Lambda code. The archive will be in the
                          format `$EXECUTABLE_NAME.zip`.

  publish                 Publish the changes to a Lambda function using a blue
                          green process.

                          If there is no existing Lambda with a matching
                          function name, this will create it for you. A role
                          will also be created with AWSLambdaBasicExecutionRole
                          access and assigned to the new Lambda.

                          If the Lambda already exists, it's code will simply
                          be updated.

                          We test that the Lambda doesn't have any startup
                          errors by using the Invoke API, please check the
                          `aws-deploy invoke --help` for reference. If invoking
                          the function does not abort abnormally, the supplied
                          alias (the default is `development`) will be updated
                          to point to the new version of the Lambda.

  invoke                  Invoke your Lambda. This is used in the publishing
                          process to verify that the Lambda is still running
                          properly before the alias is updated.
                          You could also use this when debugging.
  build-and-publish (default)
                          Run both build and publish commands in one shot.
                          `aws-deploy build-and-publish` supports all options
                          from both commands. Please see the `aws-deploy build
                          --help` and `aws-deploy publish --help` for a full
                          reference.

  See 'aws-deploy help <subcommand>' for detailed help.
```
