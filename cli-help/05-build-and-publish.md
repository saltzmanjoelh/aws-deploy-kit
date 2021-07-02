```shell
OVERVIEW: Run both build and publish commands in one shot. `aws-deploy
build-and-publish` supports all options from both commands. Please see the
`aws-deploy build --help` and `aws-deploy publish --help` for a full reference.

USAGE: aws-deploy build-and-publish [--directory <directory>] [<products> ...] [--skip-products <skip-products>] [--pre-build-command <pre-build-command>] [--post-build-command <post-build-command>] [--function-role <function-role>] [--alias <alias>] [--payload <payload>]

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
  -e, --pre-build-command <pre-build-command>
                          Run a custom shell command before the build phase.
                          The command will be executed in the same source
                          directory as the product(s) that you specify. If you
                          don't specify any products and all products are
                          built, then this command will be ran with each
                          product in their source directory.
  -o, --post-build-command <post-build-command>
                          Run a custom shell command like "aws sam-deploy"
                          after the build phase. The command will be executed
                          in the same source directory as the product(s) that
                          you specify. If you don't specify any products and
                          all products are built, then this command will be ran
                          after each product is built, in their source
                          directory.
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
  -p, --payload <payload> If you don't provide a payload, an empty string will
                          be sent. Sending an empty string simply checks if the
                          function has any startup errors. It would be more
                          useful if you customize this option with a JSON
                          string that your function can parse and run with. You
                          can provide the JSON string directly. Or if you
                          prefix the string with "file://" followed by a path
                          to a file that contains JSON, it will parse the file
                          and use it's contents.
  -h, --help              Show help information.
  ```
