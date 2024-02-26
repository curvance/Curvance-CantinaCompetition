# Invariants being Tested

## Failed Invariants

This testing suite helped find the following failed invariants during this review. Note that official Trail of Bits's writeup is in the report, which is currently business confidential and shared directly with Curvance. 

- VECVE-4 - Combining all continuous locks into a single continuous lock should result in identical user points before and after the operation.
- VECVE-10 - Combining non-continuous locks into continuous lock terminals should result in increased post combine user points compared to the pre combine user points.
- VECVE-18 - Combining some prior continuous locks to a non continuous terminal should result in the veCVE balance of a user equaling the user points. 
- VECVE-55 - Processing expired locks with relock should not change the number of locks a user has.
- VECVE-56 - Combining locks should not be possible when the system is shut down.
- DTOK-11 - A user attempting to repay too much should error gracefully.
- MARKET-7 - Calling updateCollateralToken where price returns PriceError should fail with PriceError.
- MARKET-35 - Liquidating an entire account should succeed with the correct preconditions.
- VECVE-17 - Combining no prior continuous locks to a non continuous terminal should result in no change in user points.

## Current Changes

Due to a recent rebase (on Feb 26th) with changes to the MarketManager, inlcuding the removal of the `closePosition` function, some invariants are failing because the preconditions need to be adjusted to account for the automatic pruning of the position. 

There are also incoming changes that need to be made to soft liquidations (liquidating through the DToken contract), and interest accrual that needs another adjustment to pull the internal individual account exchange rate, as opposed to the global one. 

## Stateful Deployment Tests

| ID      | Description                                                             | Status |
|---------|-------------------------------------------------------------------------|--------|
| CURV-1  | The central registry has the daoAddress set to the deployer.             | Passed |
| CURV-2  | The central registry has the timelock address set to the deployer.       | Passed |
| CURV-3  | The central registry has the emergency council address set to the deployer. | Passed |
| CURV-4  | The central registry’s genesis Epoch is equal to zero.                   | Passed |
| CURV-5  | The central registry’s sequencer is set to address(0).                   | Passed |
| CURV-6  | The central registry has granted the deployer permissions.               | Passed |
| CURV-7  | The central registry has granted the deployer elevated permissions.      | Passed |
| CURV-8  | The central registry has the cve address setup correctly.                | Passed |
| CURV-9  | The central registry has the veCVE address setup correctly.              | Passed |
| CURV-10 | The central registry has the cveLocker setup correctly.                  | Passed |
| CURV-11 | The central registry has the protocol messaging hub setup correctly.     | Passed |
| CURV-12 | The CVE contract is mapped to the centralRegistry correctly.             | Passed |
| CURV-13 | The CVE contract’s team address is set to the deployer.                  | Passed |
| CURV-14 | The CVE’s dao treasury allocation is set to 10000 ether.                 | Passed |
| CURV-15 | The CVE dao’s team allocation per month is greater than zero.            | Passed |
| CURV-16 | The Market Manager’s gauge pool is set up correctly.                     | Passed |


## FuzzVECVE – Functional Invariants
| ID       | Description                                                                                                            | Result |
|----------|------------------------------------------------------------------------------------------------------------------------|--------|
| VECVE-1  | Creating a lock with a specified amount when the system is not in a shutdown state should succeed, with preLockCVEBalance matching postLockCVEBalance + amount and preLockVECVEBalance + amount matching postLockVECVEBalance. | Passed |
| VECVE-2  | Creating a lock with an amount less than WAD should fail and revert with an error message indicating invalid lock amount. | Passed |
| VECVE-3  | Creating a lock with zero amount should fail and revert with an error message indicating an invalid lock amount. | Passed |
| VECVE-4  | Combining all continuous locks into a single continuous lock should result in identical user points before and after the operation. | FAILED |
| VECVE-5  | Combining all continuous locks into a single continuous lock should result in an increase in user points being greater than veCVE balance * MULTIPLIER / WAD. | Passed |
| VECVE-6  | Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0. | Passed |
| VECVE-7  | Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0. | Passed |
| VECVE-8  | Combining all non-continuous locks into a single non-continuous lock should result in the combined lock amount matching the sum of original lock amounts. | Passed |
| VECVE-9  | Combining all continuous locks into a single continuous lock should result in resulting user points times the CL_POINT_MULTIPLIER being greater than or equal to the balance of veCVE. | Passed |
| VECVE-10 | Combining non-continuous locks into continuous lock terminals should result in increased post combine user points compared to the pre combine user points. | FAILED |
| VECVE-11 | Combining non-continuous locks into continuous lock terminals should result in the userUnlockByEpoch value decreasing for each respective epoch. | Passed |
| VECVE-12 | Combining non-continuous locks into continuous lock terminals should result in chainUnlockByEpoch decreasing for each respective epoch. | Passed |
| VECVE-13 | Combining non-continuous locks to continuous locks should result in chainUnlockByEpochs being equal to 0. | Passed |
| VECVE-14 | Combining non-continuous locks to continuous locks should result in the userUnlocksByEpoch being equal to 0. | Passed |
| VECVE-15 | Combining any locks to a non continuous terminal should result in the amount for the combined terminal matching the sum of original lock amounts. | Passed |
| VECVE-16 | Combining some continuous locks to a non continuous terminal should result in user points decreasing. | Passed |
| VECVE-17 | Combining no prior continuous locks to a non continuous terminal should result in no change in user points. | FAILED |
| VECVE-18 | Combining some prior continuous locks to a non continuous terminal should result in the veCVE balance of a user equaling the user points. | FAILED |
| VECVE-19 | Processing an expired lock should fail when the lock index is incorrect or exceeds the length of created locks. | Passed |
| VECVE-20 | Disabling a continuous lock for a user’s continuous lock results in a decrease of user points. | Passed |
| VECVE-21 | Disable continuous lock for a user’s continuous lock results in a decrease of chain points. | Passed |
| VECVE-22 | Disable continuous lock for a user’s continuous lock results in an increase of amount to chainUnlocksByEpoch. | Passed |
| VECVE-23 | Disable continuous lock should for a user’s continuous lock results in  preUserUnlocksByEpoch + amount matching postUserUnlocksByEpoch | Passed |
| VECVE-24 | Trying to extend a lock that is already continuous should fail and revert with an error message indicating a lock type mismatch. | Passed |
| VECVE-25 | Trying to extend a lock when the system is in shutdown should fail and revert with an error message indicating that the system is shut down. | Passed |
| VECVE-26 | Shutting down the contract when the caller has elevated permissions should result in the veCVE.isShutdown = 2 | Passed |
| VECVE-27 | Shutting down the contract when the caller has elevated permissions should result in the cveLocker.isShutdown = 2 | Passed |
| VECVE-28 | Shutting down the contract when the caller has elevated permissions, and the system is not already shut down should never revert unexpectedly. | Passed |
| VECVE-29 | Calling extendLock with continuousLock set to 'true' should set the post extend lock time to CONTINUOUS_LOCK_VALUE. | Passed |
| VECVE-30 | Calling extendLock for noncontinuous extension in the same epoch should not change the unlock epoch. | Passed |
| VECVE-31 | Calling extendLock for noncontinuous extension in a future epoch should increase the unlock time. | Passed |
| VECVE-32 | Calling extendLock with correct preconditions should not revert. | Passed |
| VECVE-33 | Increasing the amount and extending the lock should succeed if the lock is continuous. | Passed |
| VECVE-34 | Increasing the lock amount and extending a continuous lock's validity should succeed, with preLockCVEBalance matching postLockCVEBalance + amount | Passed |
| VECVE-35 | Increasing the lock amount and extending a continuous lock's validity should succeed, with preLockVECVEBalance + amount matching postLockVECVEBalance. | Passed |
| VECVE-36 | Increasing the amount and extending the lock should succeed if the lock is non-continuous. | Passed |
| VECVE-37 | Increasing the lock amount and extending a non-continuous lock's validity should succeed, with preLockCVEBalance matching postLockCVEBalance + amount | Passed |
| VECVE-38 | Increasing the lock amount and extending a non-continuous lock's validity should succeed, with preLockVECVEBalance + amount matching postLockVECVEBalance. | Passed |
| VECVE-39 | Processing an expired lock for an existing lock in a shutdown contract should complete successfully | Passed |
| VECVE-40 | Processing a lock in a shutdown contract results in decreasing user points | Passed |
| VECVE-41 | Processing a lock in a shutdown contract results in decreasing chain points | Passed |
| VECVE-42 | Processing a non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch | Passed |
| VECVE-43 | Processing a non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch | Passed |
| VECVE-44 | Processing a lock in a shutdown contract results in increasing cve tokens | Passed |
| VECVE-45 | Processing a lock in a shutdown contract results in decreasing vecve tokens | Passed |
| VECVE-46 | Processing a lock in a shutdown contract results in decreasing number of user locks | Passed |
| VECVE-47 | Processing a lock should complete successfully if unlock time is expired. | Passed |
| VECVE-48 | Processing a lock in a shutdown contract results in decreasing chain points | Passed |
| VECVE-49 | Processing a non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch | Passed |
| VECVE-50 | Processing a non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch | Passed |
| VECVE-51 | Processing an expired lock without a relocking option results in increasing cve tokens | Passed |
| VECVE-52 | Processing an expired lock without a relocking option results in decreasing vecve tokens | Passed |
| VECVE-53 | Processing an expired lock without relocking should result in user points being equal. | Passed |
| VECVE-54 | Processing an expired lock without relocking should result in chain points being equal if epochs to claim = 0. | Passed |
| VECVE-55 | Processing expired locks with relock should not change the number of locks a user has. | FAILED |
| VECVE-56 | Combining locks should not be possible when the system is shut down. | FAILED |
| VECVE-57 | Processing expired locks without relocking should decrease user points if epoch to claim > 0. | Passed |
| VECVE-58 | Creating a lock with the correct preconditions should not revert. | Passed |
| VECVE-59 | Combining non-continuous locks to continuous locks should be successful with correct preconditions. | FAILED |
| VECVE-60 | Combining some prior continuous locks to non continuous terminals should be successful with correct preconditions. | FAILED |


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

| ID        | Property                                                                                                                     | Result |
|-----------|-----------------------------------------------------------------------------------------------------------------------------|--------|
| MARKET-1  | Once a new token is listed, isListed(mtoken) should return true.                                                             | Passed |
| MARKET-2  | A token already added to the MarketManager cannot be added again.                                                            | Passed |
| MARKET-3  | A user can deposit into an mtoken provided that they have the underlying asset, and they have approved the mtoken contract.  | Passed |
| MARKET-4  | When depositing assets into the mtoken, the wrapped token balance for the user should increase.                              | Passed |
| MARKET-5  | Calling updateCollateralToken with variables in the correct bounds should succeed.                                            | Passed |
| MARKET-6  | Calling updateCollateralToken with divergence in prices too large should fail with PriceError.                                | Passed |
| MARKET-7  | Calling updateCollateralToken where price returns PriceError should fail with PriceError.                                     | FAILED |
| MARKET-8  | Calling updateCollateralToken on a token with a non-zero collateral ratio should not allow the new collateral ratio to be set to zero. | Passed |
| MARKET-9  | Setting the collateral caps for a token should increase the globally set value for the specific token.                         | Passed |
| MARKET-10 | Setting collateral caps for a token given permissions and collateral values being set should succeed.                          | Passed |
| MARKET-12 | With the correct bounds on input, updateCollateralToken should revert if the price feed is out of date.                        | Passed |
| MARKET-13 | After collateral is posted, the user’s collateral posted position for the respective asset should increase.                   | Passed |
| MARKET-14 | After collateral is posted, calling hasPosition on the user’s mtoken should return true.                                      | Passed |
| MARKET-15 | After collateral is posted, the global collateral for the mtoken should increase by the amount posted.                        | Passed |
| MARKET-16 | When price feed is up to date, address(this) has mtoken, tokens are bound correctly, and caller is correct, the postCollateral call should succeed. | Passed |
| MARKET-17 | Trying to post too much collateral should revert.                                                                           | Passed |
| MARKET-14 | Removing collateral from the system should decrease the global posted collateral by the removed amount.                       | Passed |
| MARKET-15 | Removing collateral from the system should reduce the user posted collateral by the removed amount.                           | Passed |
| MARKET-16 | If the user has a liquidity shortfall, the user should not be permitted to remove collateral (function should fail with insufficient collateral selector hash). | Passed |
| MARKET-17 | Removing collateral for a nonexistent position should revert with invariant error hash.                                       | Passed |
| MARKET-18 | Removing collateral from the system should decrease the global posted collateral by the removed amount.                       | Passed |
| MARKET-19 | Removing collateral from the system should reduce the user posted collateral by the removed amount.                           | Passed |
| MARKET-20 | If the user has a liquidity shortfall, the user should not be permitted to remove collateral (function should fail with insufficient collateral selector hash). | Passed |
| MARKET-21 | If the user does not have a liquidity shortfall and meets expected preconditions, the removeCollateral should be successful. | Passed |
| MARKET-22 | If new collateral for user after removing is = 0 and a user wants to close position, the user should no longer have a position in the asset | Passed |
| MARKET-23 | Removing collateral for a nonexistent position should revert with invariant error hash.                                       | Passed |
| MARKET-24 | Removing more tokens than a user has for collateral should revert with insufficient collateral hash.                          | Passed |
| MARKET-25 | Calling reduceCollateralIfNecessary should fail when not called within the context of the mtoken.                             | Passed |
| MARKET-26 | Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is greater than 0. | Passed |
| MARKET-27 | Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is greater than 0. | Passed |
| MARKET-28 | Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is greater than 0. | Passed |
| MARKET-29 | Calling closePosition with correct preconditions should succeed,where collateral posted for the user is greater than 0.      | Passed |
| MARKET-30 | In a shortfall, closePosition should revert with insufficient collateral error                                                | Passed |
| MARKET-31 | Calling closePosition with correct preconditions should remove a position in the mtoken, where collateral posted for the user is equal to 0. | Passed |
| MARKET-32 | Calling closePosition with correct preconditions should set collateralPosted for the user’s mtoken to zero, where collateral posted for the user is equal to 0. | Passed |
| MARKET-33 | Calling closePosition with correct preconditions should reduce the user asset list by 1 element, where collateral posted for the user is equal to 0. | Passed |
| MARKET-34 | Calling closePosition with correct preconditions should succeed,where collateral posted for the user is equal to 0.         | Passed |
| MARKET-35 | Liquidating an entire account should succeed with the correct preconditions.                                                  | FAILED |
| MARKET-36 | Liquidating an entire account should zero out users’ balance for every collateral token they deposited.                      | Passed |
| MARKET-37 | Liquidating an entire account should remove the user’s position in every asset.                                               | Passed |
| MARKET-38 | Attempting to liquidate an entire account (hard liquidation) should fail if the collateral >= debt with NoLiquidationAvailable. | Passed |
| MARKET-39 | Attempting to liquidate an entire account (hard liquidation) should fail if a user is attempting to liquidate themselves with Unauthorized. | Passed |
| MARKET-40 | Attempting to liquidate an entire account (hard liquidation) should fail if seize is paused with Paused.                      | Passed |
| MARKET-41 | Calling removeCollateral with zero tokens should fail.                                                                      | Passed |


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

| ID        | Property                                                                                                             | Result |
|-----------|---------------------------------------------------------------------------------------------------------------------|--------|
| S-MARKET-1| A user’s cToken balance must always be greater than the total collateral posted for a ctoken.                         | Passed |
| S-MARKET-2| Market collateral posted of 0 for a token should have collateral posted for a token to be equivalent to the max collateral cap. | Passed |
| S-MARKET-3| Market collateral posted should always be less than max collateralCap for a non-zero collateral cap.                  | Passed |
| S-MARKET-4| The total supply of a token should never go down to zero once it has been listed.                                     | Passed |

## Market Manager – Liquidation Invariants 

| ID     | Property                                                                                                                | Result |
|--------|------------------------------------------------------------------------------------------------------------------------|--------|
| LIQ-1  | The baseCFactor must be bound between MIN_BASE_CFACTOR and MAX_BASE_CFACTOR                                             | Passed |
| LIQ-2  | The lFactor must be bound between 1 and WAD.                                                                            | Passed |
| LIQ-3  | The resulting cFactor be bound between baseCFactor and WAD                                                              | Passed |
| LIQ-4  | The liqBaseIncentive must be bound between MIN_LIQUIDATION_INCENTIVE and MAX_LIQUIDATION_INCENTIVE                       | Passed |
| LIQ-5  | The resulting incentive must be bound between MIN_LIQUIDATION_INCENTIVE and MAX_LIQUIDATION_INCENTIVE                    | Passed |
| LIQ-6  | If cfactor is equivalent to 0, maxAmount should be equal to the 0.                                                      | Passed |
| LIQ-7  | If cfactor is equivalent to WAD, maxAmount is equal to debtBalanceCached                                                | Passed |
| LIQ-8  | If cfactor is bound between 0 and WAD, non-inclusive, the maxAmount is bound between 0, debtBalanceCached.               | Passed |
| LIQ-9  | If the collateral token has less decimals than the debt token, amountAdjusted should be less than the debt balance.     | Passed |
| LIQ-10 | If the collateral token has more decimals than the debt token, amountAdjusted > debtBalanceCached.                       | Passed |
| LIQ-11 | If collateral token decimals has less decimals than the debtTokenDecimals, amountAdjusted < debtBalanceCached.           | Passed |
| LIQ-12 | If amountAdjusted==0, tokens to be liquidated should be equal to 0.                                                     | Passed |
| LIQ-13 | If debtToCollateralRatio==0, tokens to be liquidated should be equal to 0.                                               | Passed |


## DToken - Functional Invariants

| ID     | Property                                                                                                                                       | Result |
|--------|-----------------------------------------------------------------------------------------------------------------------------------------------|--------|
| DTOK-1 | Calling DToken.mint should succeed with correct preconditions.                                                                                | Passed |
| DTOK-2 | Underlying balance for sender DToken should decrease by amount after minting DToken.                                                           | Passed |
| DTOK-3 | Balance of the recipient after minting DToken should increase by amount * WAD/exchangeRateCached()                                              | FAILED |
| DTOK-4 | DToken totalSupply should increase by amount * WAD/exchangeRateCached() after calling DToken mint.                                              | Passed |
| DTOK-5 | The borrow function should succeed with proper preconditions, when not accruing interest.                                                       | Passed |
| DTOK-6 | If interest has not accrued, totalBorrows should increase after calling borrow.                                                                 | Passed |
| DTOK-7 | If interest has not accrued, the underlying balance of the caller should increase by amount                                                     | Passed |
| DTOK-8 | The borrow function should succeed with proper preconditions, when accruing interest.                                                           | Passed |
| DTOK-9 | If interest has accrued, the totalBorrows should increase by the amount.                                                                        | Passed |
| DTOK-10| If interest has accrued, the underlying balance should increase by amount.                                                                      | Passed |
| DTOK-11| A user attempting to repay too much should error gracefully.                                                                                    | FAILED |
| DTOK-12| The repay function should succeed with proper preconditions.                                                                                    | Passed |
| DTOK-13| Repaying any amount with no interest accruing should make totalBorrows equivalent to preTotalBorrows - amount                                   | Passed |
| DTOK-14| If a user repays with amount = 0, they zero out their accountDebt for their account.                                                            | Passed |
| DTOK-15| A user should be able to repay between 0 and their accountDebt with the repay function.                                                         |        |
| DTOK-16| A user trying to soft liquidate another account should fail with a 0 amount.                                                                    | Passed |
| DTOK-17| Repaying an amount with interest accruing should make totalBorrows equivalent to totalBorrows - preTotalBorrows - amount - (|new_exchange_rate - old_exchange_rate|*accountDebt) | Passed |
| DTOK-18| The mint function should revert if amount * WAD / exchangRate == 0, when trying to deposit to the GaugePool.                                    | Passed |


## DToken – System Invariants

| ID       | Property                                                                                                     | Result |
| -------- | ------------------------------------------------------------------------------------------------------------ | ------ |
| S-DTOK-1 | Market underlying held for a DToken must be equivalent to the balanceOf the underlying token.                | Passed |
| S-DTOK-2 | The number of decimals for the DToken must be equivalent to the number of decimals for the underlying token. | Passed |
| S-DTOK-3 | The isCToken function for a DToken must not return true.                                                     | Passed |

## So you found a failure?

Tips and tricks:

- Run both Echidna and Medusa to maximize the number of issues you find with the same test suite 
- Add `export ECHIDNA_SAVE_TRACES=true`, then run Echidna to get full traces for entire length of callsequences ([reference](https://github.com/crytic/echidna/pull/1180))
  - The reproducer file will be in `output/echidna-corpus/reproducer-traces/` and find the most recent file that highlights the property that failed 
- If Echidna or Medusa find an exploit, write a unit test with the same numbers. This can help you sanity check it. Add this unit test to the maintained unit tests.

## Coverage Limitations

### System-wide limitations

- Larger range on oracle prices – This will allow the fuzzer to explore large price deviations – the current test suite uses a default price to match the unit tests of 1e8 for each asset 
- More token interactions – A larger range of debt and collateral tokens the fuzzer can transact with, with additional assets valued in USD and ETH would be meaningful for the rest of the system. This can also include decimal checks.
- Larger input ranges – Input ranges being expanded to test entire full range of inputs (i.e: for uint256, testing the full range of 0 - type(uint256).max
 
### VeCVE limitations

- Additional system invariants – chainPoints being equal to a user’s (CVE locked as noncontinuous) + CVE locked / continuousPoint Multiplier
- Additional coverage on delegation functions – These include enhanced coverage for  createLockFor and increaseAmountAndExtendLockFor, in addition to  
- Pre- and post-conditions for additional functions - Some functions such as earlyExpire, and a few other introduced after we started our fuzzing campaign were not scoped for pre- and post-conditions and are missing in coverage 
- Rewards data – Currently, the system tests test against a default reward data of no reward and empty bytes. Given changes implemented in the rewards claiming on the VeCVE side, the fuzzing suite is missing coverage on these functions. 
- Full range of uint values on inputs – The createLock function for example, is currently only bound at uint64. The upper bounds of the input should be extended with the current fuzzing suite. 

### Market Manager limitations

- Partner gauges – The system does not test the GaugePool, and its interactions with partner gauges. 
- Removing collateral with a shortfall – There is coverage currently missing on removing collateral with a shortfall > 0, which may need additional tweaking with respect to system state. 
- Market Manager State Checks – missing coverage on canLiquidate and canLiquidateWithExecution functions 


## Installation Requirements

1. [Slither](https://github.com/crytic/slither/)/[crytic-compile](https://github.com/crytic/crytic-compile)
2. Echidna (currently running on echidna:master instead of release for reproducer traces - [binaries here](https://github.com/crytic/echidna/actions/runs/7804412004))
3. Medusa (see subsection below)
4. Foundry
5. Cloudexec

see:
https://github.com/curvance/curvance-contracts/blob/1ec341b7e3c2408abf3f3853a5a8145fc6bd67c3/cloudexec.toml#L8

### Medusa Installation 

There have been a significant number of changes for Medusa, which means we have not been using the latest release version. See below for installation instructions. The following assumes that you have golang installed. See [instructions](https://github.com/crytic/medusa/tree/dev/fix-call-seq-resolution?tab=readme-ov-file#building-from-source) for building from source. 

```bash 
git clone https://github.com/crytic/medusa.git
git checkout dev/fix-call-seq-resolution
go build
```

### Installing cloudexec 

We use [cloudexec](https://github.com/crytic/cloudexec) to run this fuzzing suite on the server. 

1. Follow the installation instructions through brew or release [here](https://github.com/crytic/cloudexec?tab=readme-ov-file#installation).

```bash
brew tap trailofbits/tools
brew install cloudexec
```

2. Setup your cloudexec configuration for Digital Ocean as outlined in the README [here](https://github.com/crytic/cloudexec?tab=readme-ov-file#configure-credentials).

This should include: 
- A DigitalOcen API Key 
- A DigitalOcean Spaces Key
- A DigitalOcean Secret Access Key
- A DigitalOcean Spaces Region 

## Running the Fuzzers

1. Download the corpus.zip file, temporarily linked [here](https://drive.google.com/file/d/1UQ5W6jXYDL9orqF0Pxy0TM1on7sujIrC/view)
2. Unzip this into the root `curvance/` directory

### Echidna

There are two flavours of the config provided in this code. See below for their differences

### Echidna – Locally

```bash
make el
make echidna-local
```

See [./tests/fuzzing/echidna-local.yaml](./tests/fuzzing/echidna-local.yaml) for yaml.

The main difference here is the shortened number of runs, so we can run a quick sanity check or verify that properties pass locally while running 

### Echidna – Cloud

```bash
make ec
make echidna-cloud
```

The following values encompass our historical test limit with Echidna. Note that this will depend on compute power, and resources available. The initial jobs below were deployed on a DigitalOcean droplet with 8 cores, and were then expanded to 16 core machines. Note that these times may be relative, and a fuzzing run may actually run significantly faster or slower than expected. This will depend on the value generation for this specific instance. 
- For 12-14 hour runs, our historical test limit has been around 10,000,000 iterations. 
- For 50+ hour runs, our historical test limit has been around 50,000,000 iterations. 
- For 10 day runs, our historical test limit has been around 100,000,000,000 iterations. 

### Medusa – Locally

```bash
make ml
make medusa-local
```

Unlike Echidna, Medusa's config takes the `timeout`, which defines how long to run the fuzzing campaign instead of how many iterations to attempt. This affords us visibility into finetuning the precise amount of time to run. In the early stages of the engagement, Medusa's out of memory bug was affecting Medusa's ability to run efficiently on the system, which limited our runs to 2 hour intervals each time. 

### Medusa – Cloud

```bash
make mc
make medusa-cloud
```

Our cloud runs have extended significantly since the fixing the out of memory bug in Medusa. Increasing the number of workers in Medusa scales the compute needed on the DigitalOcean droplet. Thus, Medusa runs in the following intervals: 
- 12-14 hours 
- 50+ hours 
- 10 day runs (during project breaks)
