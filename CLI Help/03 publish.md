```shell
If there is no existing Lambda with a matching function name, this will create
it for you. A role will also be created with AWSLambdaBasicExecutionRole access
and assigned to the new Lambda.

If the Lambda already exists, it's code will simply be updated.

We test that the Lambda doesn't have any startup errors by using the Invoke
API, please check the `aws-deploy invoke --help` for reference. If invoking the
function does not abort abnormally, the supplied alias (the default is
`development`) will be updated to point to the new version of the Lambda.


USAGE: aws-deploy publish [--directory <directory>]

OPTIONS:
  -d, --directory <directory>
                          Provide a custom path to the project directory
                          instead of using the current working directory.
                          (default: ./)
  -h, --help              Show help information.
```
