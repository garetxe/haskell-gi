#!/usr/bin/env bash

set -e

clean()
{
    for mod in $@; do
        pushd $mod > /dev/null
        rm -rf GI
	rm -rf dist
        rm -rf dist-newstyle
        rm -rf .stack-work
        rm -f *.cabal
        rm -f Setup.hs
        rm -f stack.yaml
        rm -f LICENSE
        rm -f README.md
	popd > /dev/null
    done
}

clean $(./AllPKGS.sh)
