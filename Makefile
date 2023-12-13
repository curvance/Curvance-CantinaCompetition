echidna-local: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/FuzzingSuite.sol --contract FuzzingSuite --config tests/fuzzing/echidna-local.yaml

echidna-cloud: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/FuzzingSuite.sol --contract FuzzingSuite --config tests/fuzzing/echidna-cloud.yaml

medusa-local: 
	medusa fuzz --config medusa-local.json
	open output/medusa-corpus/coverage_report.html

medusa-cloud: 
	medusa fuzz --config medusa-cloud.json