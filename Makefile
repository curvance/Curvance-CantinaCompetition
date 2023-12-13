echidna-local: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/FuzzingSuite.sol --contract FuzzingSuite --config tests/fuzzing/local.yaml

echidna-cloud: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/FuzzingSuite.sol --contract FuzzingSuite --config tests/fuzzing/cloud.yaml	

medusa-local: 
	medusa fuzz --config medusa-local.json

medusa-cloud: 
	medusa fuzz --config medusa-cloud.json