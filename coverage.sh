#!/bin/bash
forge coverage --report lcov
lcov --remove lcov.info  -o lcov.info 'tests/*' 'script/*' '**/libraries/external/*' '**/testnet/*' 'mocks/*'
genhtml lcov.info -o coverage_report
google-chrome --headless --window-size=1200,800 --screenshot="coverage_report/coverage.png" "coverage/index.html"
printf "<img src=\"coverage.png\"/>" > coverage_report/README.md
open coverage_report/index.html
