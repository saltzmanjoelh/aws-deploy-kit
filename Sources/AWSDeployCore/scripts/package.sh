#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftAWSLambdaRuntime open source project
##
## Copyright (c) 2020 Apple Inc. and the SwiftAWSLambdaRuntime project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eu

scripts=$(dirname "$0")
workspace="$1"
buildCommand=""
for executable in ${@: 2}; do
    echo "Copying target: $executable"
    target=".build/lambda/$executable"
    rm -rf "$target"
    mkdir -p "$target"
    cp ".build/release/$executable" "$target/"
    echo "Adding deps"
    # add the target deps based on ldd
    ldd ".build/release/$executable" | grep swift | awk '{print $3}' | xargs cp -Lv -t "$target"
    envPath="$PWD/Sources/$executable/.env"
    echo "Checking for env at: $envPath"
    if [ -f "$envPath" ]; then
        echo "Copying .env to $target/.env"
        cp "$envPath" "$target/.env"
    fi
    cd "$target"
    zipName="$PWD/${executable}_$(TZ=":UTC" date +'%y%m%d_%H%M').zip"
    ln -s "$executable" "bootstrap"
    zip --symlinks $zipName * .env
    echo -e "Built product at:\n$zipName"

done

