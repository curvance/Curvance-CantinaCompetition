#!/bin/bash
forge coverage --report lcov
lcov --remove lcov.info  -o lcov.info 'tests/*' 'script/*' '**/libraries/external/*' '**/testnet/*'
genhtml lcov.info -o report
open report/index.html
