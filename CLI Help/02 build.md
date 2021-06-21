```shell
OVERVIEW: Build one or more executables inside of a Docker container. It will
read your Swift package and build the executables of your choosing. If you
leave the defaults, it will build all of the executables in the package. You
can optionally choose to skip targets, or you can tell it to build only
specific targets.

The Docker image `swift:5.3-amazonlinux2` will be used by default. You can
override this by adding a Dockerfile to the root of the package's directory.

The built products will be available at `./build/lambda/$EXECUTABLE/`. You will
also find a zip in there which contains everything needed to update AWS Lambda
code. The archive will be in the format `$EXECUTABLE_NAME.zip`.


USAGE: aws-deploy build [--directory <directory>] [<products> ...] [--skip-products <skip-products>] [--publish] [--function-role <function-role>] [--alias <alias>] [--pre-build-command <pre-build-command>] [--post-build-command <post-build-command>]

ARGUMENTS:
  <products>              You can either specify which products you want to
                          include, or if you don't specify any products, all
                          will be used.

OPTIONS:
  -d, --directory <directory>
                          Provide a custom path to the project directory
                          instead of using the current working directory.
                          (default: ./)
  -s, --skip-products <skip-products>
                          By default if you don't specify any products to
                          build, all executable targets will be built. This
                          allows you to skip specific products. Use a comma
                          separted string. Example: -s SkipThis,SkipThat. If
                          you specified one or more targets, this option is not
                          applicable.
  -p, --publish           Publish to a Lambda function(s) with a blue green
                          process. A new Lambda version will be created for an
                          existing function that uses the same product name
                          from the archive. Archives are created with the
                          format '$EXECUTABLE_NAME.zip'. Next, the Lamdba will
                          be invoked to make sure that it hasn't crashed on
                          startup. Finally, the specified alias for the Lambda
                          (the default is 'development') will be updated to
                          point to the new revision. You can override the alias
                          name with -a or --alias. Please see the publish help
                          for reference.
  -f, --function-role <function-role>
                          When publishing, if you need to create the function,
                          this is the role being used to execute the function.
                          If this is a new role, it will use the
                          arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
                          policy. This policy can execute the Lambda and upload
                          logs to Amazon CloudWatch Logs (logs::CreateLogGroup,
                          logs::CreateLogStream and logs::PutLogEvents). If you
                          don't provide a value for this the default will be
                          used in the format $FUNCTION-role-$RANDOM. (default:
                          nil)
  -a, --alias <alias>     When publishing, this is the alias which will be
                          updated to point to the new release. (default:
                          development)
  -q, --pre-build-command <pre-build-command>
                          Run a custom shell command before the build phase.
                          The command will be executed in the same source
                          directory as the product(s) that you specify. If you
                          don't specify any products and all products are
                          built, then this command will be ran with each
                          product in their source directory.
  -r, --post-build-command <post-build-command>
                          Run a custom shell command like "aws sam-deploy"
                          after the build phase. The command will be executed
                          in the same source directory as the product(s) that
                          you specify. If you don't specify any products and
                          all products are built, then this command will be ran
                          after each product is built, in their source
                          directory.
  -h, --help              Show help information.
```
