#!/bin/bash
rm -rf coverage_report
rm lcov.info
forge coverage --report lcov
lcov --remove lcov.info  -o lcov.info 'tests/*' 'script/*' '**/libraries/external/*' '**/testnet/*' '**/mocks/*' '**/indexing/*'
genhtml lcov.info -o coverage_report
google-chrome --headless --window-size=1200,800 --screenshot="coverage_report/coverage.png" "coverage_report/index.html"
printf "<img src=\"coverage.png\"/>" > coverage_report/README.md
open coverage_report/index.html
