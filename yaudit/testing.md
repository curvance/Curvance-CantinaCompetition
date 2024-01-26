# yAudit testing

Adding you guys now, here’s the invariant information you asked for:

Invariants:

- VeCVE with CVELocker -> userPoints vs chainPoints, userUnlocksByEpoch vs chainUnlocksByEpoch, updated on people locking/unlocking/force unlocking/combining locks
- Lendtroller with CToken -> collateralPosted, this is done when a user deposits assets as collateral, or has assets and turns on collateralization, then borrows dTokens, or redeems their collateral
- Lendtroller with DToken -> totalSupply/totalBorrows with marketExchangeRate, we modify these values frequently through the dynamic interest rate model periodic updates, bad debt socialization on insolvent loans

## Potential Improvements

- use vm.bound instead of vm.assume, small improve
- if the max values is 100e18 use lower precision uint128, faster fuzzing

## Questions

- Go through the tests and see if there some missing
- Check out [locking part](https://docs.curvance.com/cve/cve-token/vecve#locking-cve-for-vecve) and see how it differs from curve standard. They have added continuous locking and unlocking. We should test that.

## Things to focus

CTokenBase.sol with CTokenCompounding.sol/CTokenPrimitive.sol inheriting from it
DynamicInterestRateModel.sol
LiquidityManager.sol with Lendtroller.sol inheriting from it
PositionFolding.sol
FeeAccumulator.sol
VeCVE.sol

Specifically focusing on functions/contracts parts around:
Collateral posting (depositAsCollateral, mintAsCollateral)
Liquidation Engine (Liquidate vs LiquidateExact) with lFactor calculation
Dynamic Vertex updating with getBorrowRateWithUpdate
Bad debt socialization through account liquidations, other side of liquidation engine
Management of posted collateral versus underlying assets deposited, think of it as deposited assets act like a yield optimizer, whereas posted collateral is using a portion or all of the assets as money market collateral without losing yield optimization side
Leveraging up/down with collateral posting/removal, slippage checks and any potential attack vectors around position folding special functions
Can ignore specifically layerzero integration side on fee accumulator but does the epoch fee router logic always work for a changing number of chains per epoch, is it exploitable through the usage of force unlocking token positions, what happens if somehow bot bugs out and it tries to repeat submit data, or repeat distribute fees in one epoch, etc. Stress testing fee accumulator
VeCVE already has pretty solid test coverage but with check sums order of operations even with reentry protection we need to make sure theres no isolated attack vectors around the early force unlock, zapping rewards via cve locker, or some other potential exploit, is there anyway to break invariants or get data out of sync with VeCVE, this specifically would be around breaking logic through heavy fuzzing than coverage

## Contracts

### VeCVE.sol

- ERC20 with disabled transfer functions
- using CONTINUOUS_LOCK_VALUE for continuous locking for 1 year
- has a central registry used for fetching address, permissions, values
- has cveLocker contract for claiming user rewards
- user can call functions:
  - createLock
  - extendLock
  - increaseAmountAndExtendLock
  - disableContinuousLock
  - combineLocks
  - combineAllLocks
  - processExpiredLock
  - earlyExpireLock

#### Testing

- Deployment code is fine
- Lock.t.sol could warp to expire, create lock and verify the values
- LockFor.t.sol ok
- ProcessExpiredLockTest.t.sol is not verifying relock, second param (bool relock) is never true

### CTokenBase

