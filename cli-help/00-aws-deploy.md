```swift
OVERVIEW: Build and run an executable product

SEE ALSO: swift build, swift package, swift test

USAGE: swift run <options>

ARGUMENTS:
  <executable>            The executable to run 
  <arguments>             The arguments to pass to the executable 

OPTIONS:
  -Xcc <Xcc>              Pass flag through to all C compiler invocations 
  -Xswiftc <Xswiftc>      Pass flag through to all Swift compiler invocations 
  -Xlinker <Xlinker>      Pass flag through to all linker invocations 
  -Xcxx <Xcxx>            Pass flag through to all C++ compiler invocations 
  -c, --configuration <configuration>
                          Build with configuration (default: debug)
  --build-path <build-path>
                          Specify build/cache directory 
  --cache-path <cache-path>
                          Specify the shared cache directory 
  --enable-repository-cache/--disable-repository-cache
                          Use a shared cache when fetching repositories
                          (default: true)
  -C, --chdir <chdir>
  --package-path <package-path>
                          Change working directory before any other operation 
  --multiroot-data-file <multiroot-data-file>
  --enable-prefetching/--disable-prefetching
                          (default: true)
  -v, --verbose           Increase verbosity of informational output 
  --disable-sandbox       Disable using the sandbox when executing subprocesses 
  --manifest-cache <manifest-cache>
                          Caching mode of Package.swift manifests (shared:
                          shared cache, local: package's build directory, none:
                          disabled (default: shared)
  --destination <destination>
  --triple <triple>
  --sdk <sdk>
  --toolchain <toolchain>
  --static-swift-stdlib/--no-static-swift-stdlib
                          Link Swift stdlib statically (default: false)
  --skip-update           Skip updating dependencies from their remote during a
                          resolution 
  --sanitize <sanitize>   Turn on runtime checks for erroneous behavior,
                          possible values: address, thread, undefined, scudo 
  --enable-code-coverage/--disable-code-coverage
                          Enable code coverage (default: false)
  --force-resolved-versions, --disable-automatic-resolution
                          Disable automatic resolution if Package.resolved file
                          is out-of-date 
  --enable-index-store/--disable-index-store
                          Enable or disable  indexing-while-building feature 
  --enable-parseable-module-interfaces
  --trace-resolver
  -j, --jobs <jobs>       The number of jobs to spawn in parallel during the
                          build process 
  --enable-build-manifest-caching/--disable-build-manifest-caching
                          (default: true)
  --emit-swift-module-separately
  --use-integrated-swift-driver
  --experimental-explicit-module-build
  --print-manifest-job-graph
                          Write the command graph for the build manifest as a
                          graphviz file 
  --build-system <build-system>
                          (default: native)
  --netrc
  --netrc-optional
  --netrc-file <netrc-file>
  --skip-build            Skip building the executable product 
  --build-tests           Build both source and test targets 
  --repl                  Launch Swift REPL for the package 
  --version               Show the version.
  -help, -h, --help       Show help information.

```
