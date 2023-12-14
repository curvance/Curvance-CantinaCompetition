echidna-local, el: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/FuzzingSuite.sol --contract FuzzingSuite --config tests/fuzzing/echidna-local.yaml

echidna-cloud, ec: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/FuzzingSuite.sol --contract FuzzingSuite --config tests/fuzzing/echidna-cloud.yaml

medusa-local, ml: 
	medusa fuzz --config medusa-local.json
	open output/medusa-corpus/coverage_report.html

medusa-cloud, mc: 
	medusa fuzz --config medusa-cloud.json