```shell
OVERVIEW: Invoke your Lambda. This is used in the publishing process to verify
that the Lambda is still running properly before the alias is updated.
You could also use this when debugging

USAGE: aws-deploy invoke [--directory <directory>]

OPTIONS:
  -d, --directory <directory>
                          Provide a custom path to the project directory
                          instead of using the current working directory.
                          (default: ./)
  -h, --help              Show help information.
```
