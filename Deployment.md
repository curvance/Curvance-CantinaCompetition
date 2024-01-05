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

## Deploy Curvance core contracts

```
forge script ./script/DeployCurvance.s.sol $network --sig "run(string)" --rpc-url $rpc --broadcast
```

## Deploy DToken

```
forge script ./script/DeployDToken.s.sol $network $symbol --sig "run(string,string)" --rpc-url $rpc --broadcast
```

## Deploy CTokenPrimitive

```
forge script ./script/DeployCTokenPrimitive.s.sol $network $symbol --sig "run(string,string)" --rpc-url $rpc --broadcast
```
