```swift
OVERVIEW: Invoke your Lambda. This is used in the publishing process to verify
that the Lambda is still running properly before the alias is updated.
You could also use this when debugging

USAGE: aws-deploy invoke <function> [<payload>] [--directory <directory>] [--endpoint-url <endpoint-url>]

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
                          For invoking multiple functions, simply provide a
                          comma separated list of function names like:
                          `my-function,my-other-function`
  <payload>               If you don't provide a payload, an empty string will
                          be sent. Sending an empty string simply checks if the
                          function has any startup errors. It would be more
                          useful if you customize this option with a JSON
                          string that your function can parse and run with. You
                          can provide the JSON string directly. Or, if you
                          prefix the string with "file://" followed by a path
                          to a file that contains JSON, it will parse the file
                          and use it's contents.
                          When invoking multiple functions, you can provide a
                          single payload or file path to a payload and it will
                          be parsed for each function. Or, you can provide
                          multiple comma separated values. The values can be
                          eith payloads or file paths like:
                          `file:///path/to/payload1.json,file:///path/to/payload2.json`.
                          If you provide the directory option (`-d` or
                          `--directory`), you can use paths that are relative
                          to each function's source directory. For example, if
                          you include a file with the same name in each
                          directory for invoking with. For example `invoke
                          my-func,my-other-func file://payload.json -d
                          /path/to/project`

OPTIONS:
  -d, --directory <directory>
                          Provide a custom path to the project directory
                          instead of using the current working directory.
                          (default: ./)
  -e, --endpoint-url <endpoint-url>
                          If you leave this empty, it will use the default AWS
                          URL. You can override this with a local URL for
                          debugging.
  -h, --help              Show help information.
```
