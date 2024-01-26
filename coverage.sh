#!/bin/bash
forge coverage --report lcov
lcov --remove lcov.info  -o lcov.info 'tests/*' 'script/*' '**/libraries/external/*' '**/testnet/*'
genhtml lcov.info -o report
printf "## Last updated: $(date +%F_%T)" > report/README.md
open report/index.html
