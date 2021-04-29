#!/usr/bin/env bash
PATH="$PATH:/usr/local/bin"

scripts=$(dirname "$0")
workspace="$1"
products=${@: 2}

#echo "scripts=$scripts"
#echo "workspace=$workspace"
#echo "products=$products"

# We execute the script from within docker because the awk '{print $3}' command doesn't work correctly when passed in through bash -c "command | awk ..."
#-v "$workspace":"$workspace:delegated"
docker run -it --rm -e TERM=dumb -e GIT_TERMINAL_PROMPT=1 -v "$scripts":/scripts -v "$workspace":"$workspace" -w "$workspace" builder \
    bash -c "/scripts/package.sh $workspace $products"
