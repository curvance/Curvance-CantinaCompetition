echidna-local: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/EchidnaBaseMarket.sol --contract EchidnaBaseMarket --config tests/fuzzing/local.yaml

echidna-cloud: 
	rm -rf crytic-export
	forge clean
	echidna tests/fuzzing/EchidnaBaseMarket.sol --contract EchidnaBaseMarket --config tests/fuzzing/cloud.yaml	

medusa-local: 
	medusa fuzz