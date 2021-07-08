```swift
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


USAGE: aws-deploy build [--directory <directory>] [<products> ...] [--skip-products <skip-products>] [--pre-build-command <pre-build-command>] [--post-build-command <post-build-command>] [--ssh-key-path <ssh-key-path>]

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
  -k, --ssh-key-path <ssh-key-path>
                          Specify an SSH key for private repos. Since we are
                          building inside Docker, your usual .ssh directory is
                          not available inside the container. Example: -k
                          /home/user/.ssh/my_key
  -h, --help              Show help information.
```
