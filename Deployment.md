# Deployment scripts

## Deploy mock token/aggregator

Deploy mock token
```
forge script ./script/mocks/DeployMockToken.s.sol $network $name $symbol $decimals --sig "run(string,string,string,uint8)"  --rpc-url $rpc --broadcast
```

Deploy mock token aggregator
```
forge script ./script/mocks/DeployMockV3Aggregator.s.sol $network $name $decimals $initialAnswer $maxAnswer $minAnswer --sig "run(string,string,uint8,int256,int192,int192)"  --rpc-url $rpc --broadcast
```

* here name is not token name or symbol, use something like `USDC-Aggregator`
