
#### /contracts/compound/CErc20.sol

```
    /// TODO Should this be nonReentrant?
    function redeem(uint256 redeemTokens) external override {
        redeemInternal(redeemTokens);
    }
```

redeemInternal function has nonReentrant modifier, so no need to add nonReentrant again here.

