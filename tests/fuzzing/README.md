# Invariants being Tested

## Stateful Deployment Tests

| ID      | Property                                                                    | Result |
| ------- | --------------------------------------------------------------------------- | ------ |
| CURV-1  | The central registry has the daoAddress set to the deployer.                | Passed |
| CURV-2  | The central registry has the timelock address set to the deployer.          | Passed |
| CURV-3  | The central registry has the emergency council address set to the deployer. | Passed |
| CURV-4  | The central registry’s genesis Epoch is equal to zero.                      | Passed |
| CURV-5  | The central registry’s sequencer is set to address(0).                      | Passed |
| CURV-6  | The central registry has granted the deployer permissions.                  | Passed |
| CURV-7  | The central registry has granted the deployer elevated permissions.         | Passed |
| CURV-8  | The central registry has the cve address setup correctly.                   | Passed |
| CURV-9  | The central registry has the veCVE address setup correctly.                 | Passed |
| CURV-10 | The central registry has the cveLocker setup correctly.                     | Passed |
| CURV-11 | The central registry has the protocol messaging hub setup correctly.        | Passed |
| CURV-12 | The CVE contract is mapped to the centralRegistry correctly.                | Passed |
| CURV-13 | The CVE contract’s team address is set to the deployer.                     | Passed |
| CURV-14 | The CVE’s dao treasury allocation is set to 10000 ether.                    | Passed |
| CURV-15 | The CVE dao’s team allocation per month is greater than zero.               | Passed |
| CURV-16 | The Lendtroller’s gauge pool is set up correctly.                           | Passed |

## FuzzVECVE – Functional Invariants

| ID        | Property                                                                                                                                                                                                                       | Result |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| VECVE-1   | Creating a lock with a specified amount when the system is not in a shutdown state should succeed, with preLockCVEBalance matching postLockCVEBalance + amount and preLockVECVEBalance + amount matching postLockVECVEBalance. | Passed |
| VECVE-2   | Creating a lock with an amount less than WAD should fail and revert with an error message indicating invalid lock amount.                                                                                                      | Passed |
| VECVE-3   | Creating a lock with zero amount should fail and revert with an error message indicating an invalid lock amount.                                                                                                               | Passed |
| VECVE-4   | Combining all continuous locks into a single continuous lock should result in identical user points before and after the operation.                                                                                            | FAILED |
| VECVE-5   | Combining all continuous locks into a single continuous lock should result in an increase in user points being greater than veCVE balance \* MULTIPLIER / WAD.                                                                 | Passed |
| VECVE-6   | Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.                                                                                                            | Passed |
| VECVE-7   | Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.                                                                                                            |        |
| VECVE-8   | Combining all non-continuous locks into a single non-continuous lock should result in the combined lock amount matching the sum of original lock amounts.                                                                      | Passed |
| VECVE-9   | Combining all continuous locks into a single continuous lock should result in resulting user points times the CL_POINT_MULTIPLIER being greater than or equal to the balance of veCVE.                                         | Passed |
| VECVE-10  | Combining non-continuous locks into continuous lock terminals should result in increased post combine user points compared to the pre combine user points.                                                                     | FAILED |
| VECVE-11  | Combining non-continuous locks into continuous lock terminals should result in the userUnlockByEpoch value decreasing for each respective epoch.                                                                               | Passed |
| VECVE-12  | Combining non-continuous locks into continuous lock terminals should result in chainUnlockByEpoch decreasing for each respective epoch.                                                                                        | Passed |
| VECVE-13  | Combining non-continuous locks to continuous locks should result in chainUnlockByEpochs being equal to 0.                                                                                                                      | Passed |
| VECVE-14  | Combining non-continuous locks to continuous locks should result in the userUnlocksByEpoch being equal to 0.                                                                                                                   | Passed |
| VECVE-15  | Combining any locks to a non continuous terminal should result in the amount for the combined terminal matching the sum of original lock amounts.                                                                              | Passed |
| VECVE-16  | Combining some continuous locks to a non continuous terminal should result in user points decreasing.                                                                                                                          | Passed |
| VECVE-17  | Combining no prior continuous locks to a non continuous terminal should result in no change in user points.                                                                                                                    | Passed |
| VECVE-18  | Combining some prior continuous locks to a non continuous terminal should result in the veCVE balance of a user equaling the user points.                                                                                      | FAILED |
| VECVE-19  | Processing an expired lock should fail when the lock index is incorrect or exceeds the length of created locks.                                                                                                                | Passed |
| VECVE-20  | Disabling a continuous lock for a user’s continuous lock results in a decrease of user points.                                                                                                                                 | Passed |
| VECVE-21  | Disable continuous lock for a user’s continuous lock results in a decrease of chain points.                                                                                                                                    | Passed |
| VECVE-22  | Disable continuous lock for a user’s continuous lock results in an increase of amount to chainUnlocksByEpoch.                                                                                                                  | Passed |
| VECVE-23  | Disable continuous lock should for a user’s continuous lock results in preUserUnlocksByEpoch + amount matching postUserUnlocksByEpoch                                                                                          | Passed |
| VECVE-24  | Trying to extend a lock that is already continuous should fail and revert with an error message indicating a lock type mismatch.                                                                                               | Passed |
| VECVE-25  | Trying to extend a lock when the system is in shutdown should fail and revert with an error message indicating that the system is shut down.                                                                                   | Passed |
| VECVE-26  | Shutting down the contract when the caller has elevated permissions should result in the veCVE.isShutdown = 2                                                                                                                  | Passed |
| VECVE-27  | Shutting down the contract when the caller has elevated permissions should result in the cveLocker.isShutdown = 2                                                                                                              | Passed |
| VECVE-28  | Shutting down the contract when the caller has elevated permissions, and the system is not already shut down should never revert unexpectedly.                                                                                 | Passed |
| VECVE-29  | Calling extendLock with continuousLock set to 'true' should set the post extend lock time to CONTINUOUS_LOCK_VALUE.                                                                                                            | Passed |
| VECVE-30  | Calling extendLock for noncontinuous extension in the same epoch should not change the unlock epoch.                                                                                                                           | Passed |
| VECVE-31  | Calling extendLock for noncontinuous extension in a future epoch should increase the unlock time.                                                                                                                              | Passed |
| VECVE-32  | Calling extendLock with correct preconditions should not revert.                                                                                                                                                               | Passed |
| VECVE-33  | Increasing the amount and extending the lock should succeed if the lock is continuous.                                                                                                                                         | Passed |
| VECVE-34  | Increasing the lock amount and extending a continuous lock's validity should succeed, with preLockCVEBalance matching postLockCVEBalance + amount                                                                              | Passed |
| VECVE-35  | Increasing the lock amount and extending a continuous lock's validity should succeed, with preLockVECVEBalance + amount matching postLockVECVEBalance.                                                                         | Passed |
| VECVE-36  | Increasing the amount and extending the lock should succeed if the lock is non-continuous.                                                                                                                                     | Passed |
| VECVE-37  | Increasing the lock amount and extending a non-continuous lock's validity should succeed, with preLockCVEBalance matching postLockCVEBalance + amount                                                                          | Passed |
| VECVE-38  | Increasing the lock amount and extending a non-continuous lock's validity should succeed, with preLockVECVEBalance + amount matching postLockVECVEBalance.                                                                     | Passed |
| VECVE-39  | Processing an expired lock for an existing lock in a shutdown contract should complete successfully                                                                                                                            | Passed |
| VE-CVE-40 | Processing a lock in a shutdown contract results in decreasing number of user locks                                                                                                                                            | Passed |
| VECVE-41  | Processing a lock in a shutdown contract results in decreasing chain points                                                                                                                                                    | Passed |
| VECVE-42  | Processing a non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch                                                                                      | Passed |
| VECVE-43  | Processing a non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch                                                                                        | Passed |
| VECVE-44  | Processing a lock in a shutdown contract results in increasing cve tokens                                                                                                                                                      | Passed |
| VECVE-45  | Processing a lock in a shutdown contract results in decreasing vecve tokens                                                                                                                                                    | Passed |
| VECVE-46  | Processing a lock in a shutdown contract results in decreasing number of user locks                                                                                                                                            | Passed |
| VECVE-47  | Processing a lock should complete successfully if unlock time is expired.                                                                                                                                                      | Passed |
| VECVE-48  | Processing a lock in a shutdown contract results in decreasing chain points                                                                                                                                                    | Passed |
| VECVE-49  | Processing a non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch                                                                                      | Passed |
| VECVE-50  | Processing a non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch                                                                                        | Passed |
| VECVE-51  | Processing an expired lock without a relocking option results in increasing cve tokens                                                                                                                                         | Passed |
| VECVE-52  | Processing an expired lock without a relocking option results in decreasing vecve tokens                                                                                                                                       | Passed |
| VECVE-53  | Processing an expired lock without relocking should result in user points being equal.                                                                                                                                         | Passed |
| VECVE-54  | Processing an expired lock without relocking should result in chain points being equal.                                                                                                                                        | Passed |
| VECVE-55  | Processing expired locks with relock should not change the number of locks a user has.                                                                                                                                         | FAILED |
| VECVE-56  | Combining locks should not be possible when the system is shut down.                                                                                                                                                           | FAILED |

## FuzzVECVE – System Invariants

| ID        | Property                                                                                        | Result |
| --------- | ----------------------------------------------------------------------------------------------- | ------ |
| S-VECVE-1 | Balance of veCVE must equal to the sum of all non-continuous lock amounts.                      | Passed |
| S-VECVE-2 | User unlocks by epoch should be greater than 0 for all non-continuous locks.                    | Passed |
| S-VECVE-3 | User unlocks by epoch should be 0 for all continuous locks.                                     | Passed |
| S-VECVE-4 | Chain unlocks by epoch should be greater than 0 for all non-continuous locks.                   | Passed |
| S-VECVE-5 | Chain unlocks by epoch should be 0 for all continuous locks.                                    | Passed |
| S-VECVE-6 | The sum of all user unlock epochs for each epoch must be less than or equal to the user points. | Passed |
| S-VECVE-7 | The contract should only have a zero cve balance when there are no user locks.                  | Passed |

## Market Manager - Functional Invariants

| ID        | Property                                                                                                                                                            | Result |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| MARKET-1  | Once a new token is listed, lendtroller.isListed(mtoken) should return true.                                                                                        | Passed |
| MARKET-2  | A token already added to the Lendtroller cannot be added again.                                                                                                     | Passed |
| MARKET-3  | A user can deposit into an mtoken provided that they have the underlying asset, and they have approved the mtoken contract.                                         | Passed |
| MARKET-4  | When depositing assets into the mtoken, the wrapped token balance for the user should increase.                                                                     | Passed |
| MARKET-5  | Calling updateCollateralToken with variables in the correct bounds should succeed.                                                                                  | Passed |
| MARKET-6  | Setting the collateral caps for a token should increase the globally set value for the specific token.                                                              | Passed |
| MARKET-7  | Setting collateral caps for a token given permissions and collateral values being set should succeed.                                                               | Passed |
| MARKET-8  | With the correct bounds on input, updateCollateralToken should revert if the price feed is out of date.                                                             | Passed |
| MARKET-9  | After collateral is posted, the user’s collateral posted position for the respective asset should increase.                                                         | Passed |
| MARKET-10 | After collateral is posted, calling hasPosition on the user’s mtoken should return true.                                                                            | Passed |
| MARKET-11 | After collateral is posted, the global collateral for the mtoken should increase by the amount posted.                                                              | Passed |
| MARKET-12 | When price feed is up to date, address(this) has mtoken, tokens are bound correctly, and caller is correct, the postCollateral call should succeed.                 | Passed |
| MARKET-13 | Trying to post too much collateral should revert.                                                                                                                   | Passed |
| MARKET-14 | Removing collateral from the system should decrease the global posted collateral by the removed amount.                                                             | Passed |
| MARKET-15 | Removing collateral from the system should reduce the user posted collateral by the removed amount.                                                                 | Passed |
| MARKET-16 | If the user has a liquidity shortfall, the user should not be permitted to remove collateral (function should fail with insufficient collateral selector hash).     | Passed |
| MARKET-17 | If the user does not have a liquidity shortfall and meets expected preconditions, the removeCollateral should be successful.                                        | Passed |
| MARKET-18 | Removing collateral for a nonexistent position should revert with invariant error hash.                                                                             | Passed |
| MARKET-19 | Removing more tokens than a user has for collateral should revert with insufficient collateral hash.                                                                | Passed |
| MARKET-20 | Calling reduceCollateralIfNecessary should fail when not called within the context of the mtoken.                                                                   | Passed |
| MARKET-21 | Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is greater than 0.                    | Passed |
| MARKET-22 | Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is greater than 0. | Passed |
| MARKET-23 | Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is greater than 0.            | Passed |
| MARKET-24 | Calling closePosition with correct preconditions should succeed, where collateral posted for the user is greater than 0.                                            | Passed |
| MARKET-25 | Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is equal to 0.                        | Passed |
| MARKET-26 | Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is equal to 0.     | Passed |
| MARKET-27 | Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is equal to 0.                | Passed |
| MARKET-28 | Calling closePosition with correct preconditions should succeed, where collateral posted for the user is equal to 0.                                                | Passed |
| MARKET-29 | Calling deposit when convertToShares overflows should revert.                                                                                                       | Passed |
| MARKET-31 | Calling deposit when totalAssets + amount overflows should revert.                                                                                                  | Passed |
| MARKET-32 | Calling deposit when oracle price returns <0, deposit should revert.                                                                                                | Passed |

## Market Manager – Access Controls

| ID           | Property                                                                                  | Result |
| ------------ | ----------------------------------------------------------------------------------------- | ------ |
| AC-MARKET-1  | Calling setMintPaused with correct preconditions should not revert.                       | Passed |
| AC-MARKET-2  | Calling the setMintPaused(mtoken, true) with authorization should set isMintPaused to 2.  | Passed |
| AC-MARKET-3  | Calling the setMintPaused(mtoken, false) with authorization should set isMintPaused to 1. | Passed |
| AC-MARKET-4  | Calling setRedeemPaused with the correct preconditions should succeed.                    | Passed |
| AC-MARKET-5  | Calling setRedeemPaused(true) with authorization should set redeemPaused to 2.            | Passed |
| AC-MARKET-6  | Calling setRedeemPaused(false) with authorization should set redeemPaused to 1.           | Passed |
| AC-MARKET-7  | Calling setTransferPaused with the correct preconditions should not revert.               | Passed |
| AC-MARKET-8  | Calling setTransferPaused(true) with authorization should set transferPaused to 2.        | Passed |
| AC-MARKET-9  | Calling setTransferPaused(false) with authorization should set transferPaused to 1.       | Passed |
| AC-MARKET-10 | Calling setSeizePaused with the correct authorization should succeed.                     | Passed |
| AC-MARKET-11 | Calling setSeizePaused(true) should set seizePaused to 2.                                 | Passed |
| AC-MARKET-12 | Calling setSeizePaused(false) should set seizePaused to 1.                                | Passed |
| AC-MARKET-13 | Calling setBorrowPaused with correct preconditions should succeed.                        | Passed |
| AC-MARKET-14 | Calling setBorrowPaused(mtoken, true) should set isBorrowPaused to 2.                     | Passed |
| AC-MARKET-15 | Calling setBorrowPaused(mtoken, false) should set isBorrowPaused to 1.                    | Passed |

## Market Manager - State Checks

| ID           | Property                                                                                                                                                                     | Result |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| SC-MARKET-1  | The canMint function should not revert when mint is not paused and a token is listed in the system.                                                                          | Passed |
| SC-MARKET-2  | The canMint function should revert when the token is not listed.                                                                                                             | Passed |
| SC-MARKET-3  | The canMint function should revert when mint is paused.                                                                                                                      | Passed |
| SC-MARKET-4  | The canRedeem function should succeed when redeem is not paused, mtoken is listed, MIN_HOLD_PERIOD has passed since posting, and the user does not have a liquidity deficit. | Passed |
| SC-MARKET-5  | The canRedeem function should revert when the redeemPaused flag is set to 2.                                                                                                 | Passed |
| SC-MARKET-6  | The canRedeem function should revert when the token is not listed.                                                                                                           | Passed |
| SC-MARKET-7  | The canRedeem function should revert when a user has a liquidityDeficit greater than 0.                                                                                      | Passed |
| SC-MARKET-8  | The canRedeem function should return (no error or return) when no position exists.                                                                                           | Passed |
| SC-MARKET-9  | The canRedeemWithCollateralRemoval function should fail when not called by the mtoken address.                                                                               | Passed |
| SC-MARKET-10 | The canTransfer function should pass when all preconditions are met.                                                                                                         | Passed |
| SC-MARKET-11 | The canTransfer function should fail when transferring in the system is paused.                                                                                              | Passed |
| SC-MARKET-12 | The canTransfer function should fail when the mtoken is not listed.                                                                                                          |        |
| SC-MARKET-13 | The canTransfer function should fail when redeem is paused.                                                                                                                  | Passed |
| SC-MARKET-14 | The canBorrow function should succeed when borrow is not paused and mtoken is listed.                                                                                        | Passed |
| SC-MARKET-15 | The canBorrow function should fail when borrow is paused.                                                                                                                    | Passed |
| SC-MARKET-16 | The canBorrow function should fail when mtoken is unlisted.                                                                                                                  | Passed |
| SC-MARKET-17 | The canBorrow function should fail when a liquidity deficit exists.                                                                                                          | Passed |
| SC-MARKET-18 | The canBorrowWithNotify function should fail when called directly.                                                                                                           | Passed |
| SC-MARKET-19 | The canRepay function should succeed when mtoken is listed and MIN_HOLD_PERIOD has passed.                                                                                   | Passed |
| SC-MARKET-20 | The canRepay function should revert when mtoken is not listed.                                                                                                               | Passed |
| SC-MARKET-21 | The canRepay function should revert when MIN_HOLD_PERIOD has not passed.                                                                                                     | Passed |
| SC-MARKET-22 | The canSeize function should succeed when seize is not paused, collateral and debt token are listed, and both tokens have the same lendtroller.                              | Passed |
| SC-MARKET-23 | The canSeize function should revert when seize is paused.                                                                                                                    | Passed |
| SC-MARKET-24 | The canSeize function should revert when collateral or debt token are not listed in the Lendtroller.                                                                         | Passed |
| SC-MARKET-25 | The canSeize function should revert when both tokens do not have the same Lendtroller.                                                                                       | Passed |

## Market Manager – System Invariants

| ID         | Property                                                                                      | Result |
| ---------- | --------------------------------------------------------------------------------------------- | ------ |
| S-MARKET-1 | A user’s cToken balance must always be greater than the total collateral posted for a ctoken. | Passed |
| S-MARKET-2 | Market collateral posted should always be less than or equal to collateralCaps for a token.   | Passed |
| S-MARKET-3 | The total supply of a token should never go down to zero once it has been listed.             | Passed |

## DToken - Functional Invariants

| ID      | Property                                                                                            | Result |
| ------- | --------------------------------------------------------------------------------------------------- | ------ |
| DTOK-1  | Calling DToken.mint should succeed with correct preconditions.                                      | Passed |
| DTOK-2  | Underlying balance for sender DToken should decrease by amount after minting DToken.                | Passed |
| DTOK-3  | Balance of the recipient after minting DToken should increase by amount \* WAD/exchangeRateCached() | Passed |
| DTOK-4  | DToken totalSupply should increase by amount \* WAD/exchangeRateCached() after calling DToken mint. | Passed |
| DTOK-5  | The borrow function should succeed with proper preconditions, when not accruing interest.           | Passed |
| DTOK-6  | If interest has not accrued, totalBorrows should increase after calling borrow.                     | Passed |
| DTOK-7  | If interest has not accrued, the underlying balance of the caller should increase by amount         | Passed |
| DTOK-8  | The borrow function should succeed with proper preconditions, when accruing interest.               | Passed |
| DTOK-9  | If interest has accrued, the totalBorrows should increase by the amount.                            | Passed |
| DTOK-10 | If interest has accrued, the underlying balance should increase by amount.                          | Passed |
| DTOK-11 | The repay function should succeed with proper preconditions.                                        | Passed |
| DTOK-12 | A user attempting to repay too much should error gracefully.                                        | FAILED |
| DTOK-13 | A user should be able to repay between 0 and their accountDebt with the repay function.             | Passed |
| DTOK-14 | If a user repays with amount = 0, they zero out their accountDebt for their account.                | Passed |

## DToken – System Invariants

| ID       | Property                                                                                                     | Result |
| -------- | ------------------------------------------------------------------------------------------------------------ | ------ |
| S-DTOK-1 | Market underlying held for a DToken must be equivalent to the balanceOf the underlying token.                | Passed |
| S-DTOK-2 | The number of decimals for the DToken must be equivalent to the number of decimals for the underlying token. | Passed |
| S-DTOK-3 | The isCToken function for a DToken must not return true.                                                     | Passed |

## So you found a failure?

Tips and tricks:

- Use Echidna as the primary fuzzer
- Medusa works really well to test coverage and to debug the correct behaviour of functions
- If Echidna or Medusa find an exploit, write a unit test with the same numbers. This can help you sanity check it. Add this unit test to the maintained unit tests.

## Coverage Limitations

### System 
- oracle prices – `allContracts` was turned on at one point to allow the fuzzer to poke huge price deviations, however the test suite was not yet ready to handle this dynamic style of input. eventually, this style of function can be added to the system to test dynamic range of price feeds: 
```
    function set_price_feeds(uint256 usdcPrice, uint256 daiPrice) public {
        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
    }
```

### VECVE

- Input ranges on creation of lock does not test full range of input – would benefit from additional coverage
- Additional stateful functions can be added, including:
  - Chainpoints
    - equal to user's (CVE locked as non continuous) + (CVE locked \* continuousLock point multiplier)
  - ChainUnlocksByEpoch
    - The sum of all chainUnlocksByEpoch map values should always be <= chainPoints
    - The sum of all userPoints should be equal to chainPoints
    - The sum of all chainUnlocksByEpoch maps should be equal to the sum of all userUnlocksByEpoch maps.
- `createLockfor` and `increaseAmountAndExtendLockFor`
- `earlyExpire`
- additional tests on callers

## Market Manager

- current debt > max allowed debt after folding
- partner gauges

---

## Installation Requirements

1. Slither/crytic-compile
2. Echidna
3. Medusa
4. Foundry
5. Cloudexec

see:
https://github.com/curvance/curvance-contracts/blob/1ec341b7e3c2408abf3f3853a5a8145fc6bd67c3/cloudexec.toml#L8

## Running Echidna

There are two flavours of the config provided in this code. See below for their differences

### Echidna – Locally

```bash
make echidna-local
```

See [./tests/fuzzing/echidna-local.yaml](./tests/fuzzing/echidna-local.yaml) for yaml.

The main difference here is the shortened number of runs, so we can run a quick sanity check.

### Echidna – Cloud

```bash
make echidna-cloud
```

```yaml
testMode: exploration # run in exploration mode to increase coverage
testLimit: 10000000 # number may change, but will increase according to coverage
coverage: true # save coverage
corpusDir: "output/echidna-corpus" #save in echidna-corpus directory
cryticArgs: ["--ignore-compile"] # the contracts do not need to be re-compiled
```

The above may not always represent the exact config being used, as we may fine-tune it to run longer on weekends, etc.

### Medusa – Locally

```bash
make medusa-local
```

Notable differences:

- `timeout(# of seconds to run Medusa)`: 2 minutes

### Medusa – Cloud

```bash
make medusa-cloud
```

Notable differences:

- `timeout (# of seconds to run Medusa)`: 16 hours

### Running on Cloud

We use [cloudexec](https://github.com/crytic/cloudexec/tree/hotfix) to run this fuzzing suite on the server. As the release has not been cut yet, see below for installation:

```bash
git clone https://github.com/crytic/cloudexec.git
git checkout hotfix
make
```

Add the binary above to your PATH and you should be able to run cloudexec after sufficient setup.

Run `cloudexec pull ./output` to pull the most recent corpus runs (note that both Echidna and Medusa corpus runs have been changed to write to this directory).
