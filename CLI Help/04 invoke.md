```shell
OVERVIEW: Invoke your Lambda. This is used in the publishing process to verify
that the Lambda is still running properly before the alias is updated.
You could also use this when debugging

USAGE: aws-deploy invoke <function> [<payload>]

ARGUMENTS:
  <function>              The name of the Lambda function, version, or alias. 
                          Name formats: Function name, my-function (name-only),
                          my-function:v1 (with alias).
                          Function ARN -
                          arn:aws:lambda:us-west-2:123456789012:function:my-function.
Partial
                          ARN - 123456789012:function:my-function.
                          You can append a version number or alias to any of
                          the formats. The length constraint applies only to
                          the full ARN. If you specify only the function name,
                          it is limited to 64 characters in length.
  <payload>               If you don't provide a payload, an empty string will
                          be sent. Sending an empty string simply checks if the
                          function has any startup errors. It would be more
                          useful if you customize this option with a JSON
                          string that your function can parse and run with. You
                          can provide the JSON string directly. Or if you
                          prefix the string with "file://" followed by a path
                          to a file that contains JSON, it will parse the file
                          and use it's contents.

OPTIONS:
  -h, --help              Show help information.
```
