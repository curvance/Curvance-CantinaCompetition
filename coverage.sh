#!/bin/bash
forge coverage --report lcov
lcov --remove lcov.info  -o lcov.info 'tests/*' 'script/*' '**/libraries/external/*' '**/testnet/*'
genhtml lcov.info -o report
google-chrome --headless --screenshot="report/coverage.png" "report/index.html"
printf "<img src="coverage.png"/>" > report/README.md
open report/index.html
