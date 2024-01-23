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

| ID       | Property                                                                                                                                                                                                                       | Result |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| VECVE-1  | Creating a lock with a specified amount when the system is not in a shutdown state should succeed, with preLockCVEBalance matching postLockCVEBalance + amount and preLockVECVEBalance + amount matching postLockVECVEBalance. | Passed |
| VECVE-2  | Creating a lock with an amount less than WAD should fail and revert with an error message indicating invalid lock amount.                                                                                                      | Passed |
| VECVE-3  | Creating a lock with zero amount should fail and revert with an error message indicating an invalid lock amount.                                                                                                               | Passed |
| VECVE-4  | Combining all continuous locks into a single continuous lock should result in identical user points before and after the operation.                                                                                            | FAILED |
| VECVE-5  | Combining all continuous locks into a single continuous lock should result in an increase in user points being greater than veCVE balance * MULTIPLIER / WAD.                                                                  | Passed |
| VECVE-6  | Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.                                                                                                            | Passed |
| VECVE-7  | Combining all continuous locks into a single continuous lock should result in chainUnlocksByEpoch being equal to 0.                                                                                                            | Passed |
| VECVE-8  | Combining all non-continuous locks into a single non-continuous lock should result in the combined lock amount matching the sum of original lock amounts.                                                                      | Passed |
| VECVE-9  | Combining all continuous locks into a single continuous lock should result in resulting user points times the CL_POINT_MULTIPLIER being greater than or equal to the balance of veCVE.                                         | Passed |
| VECVE-10 | Combining non-continuous locks into continuous lock terminals should result in increased post combine user points compared to the pre combine user points.                                                                     | FAILED |
| VECVE-11 | Combining non-continuous locks into continuous lock terminals should result in the userUnlockByEpoch value decreasing for each respective epoch.                                                                               | Passed |
| VECVE-12 | Combining non-continuous locks into continuous lock terminals should result in chainUnlockByEpoch decreasing for each respective epoch.                                                                                        | Passed |
| VECVE-13 | Combining non-continuous locks to continuous locks should result in chainUnlockByEpochs being equal to 0.                                                                                                                      | Passed |
| VECVE-14 | Combining non-continuous locks to continuous locks should result in the userUnlocksByEpoch being equal to 0.                                                                                                                   | Passed |
| VECVE-15 | Combining any locks to a non continuous terminal should result in the amount for the combined terminal matching the sum of original lock amounts.                                                                              | Passed |
| VECVE-16 | Combining some continuous locks to a non continuous terminal should result in user points decreasing.                                                                                                                          | Passed |
| VECVE-17 | Combining no prior continuous locks to a non continuous terminal should result in no change in user points.                                                                                                                    | Passed |
| VECVE-18 | Combining some prior continuous locks to a non continuous terminal should result in the veCVE balance of a user equaling the user points.                                                                                      | Passed |
| VECVE-19 | Processing an expired lock should fail when the lock index is incorrect or exceeds the length of created locks.                                                                                                                | Passed |
| VECVE-20 | Disabling a continuous lock for a user’s continuous lock results in a decrease of user points.                                                                                                                                 | Passed |
| VECVE-21 | Disable continuous lock for a user’s continuous lock results in a decrease of chain points.                                                                                                                                    | Passed |
| VECVE-22 | Disable continuous lock for a user’s continuous lock results in an increase of amount to chainUnlocksByEpoch.                                                                                                                  | Passed |
| VECVE-23 | Disable continuous lock should for a user’s continuous lock results in  preUserUnlocksByEpoch + amount matching postUserUnlocksByEpoch                                                                                         | Passed |
| VECVE-24 | Trying to extend a lock that is already continuous should fail and revert with an error message indicating a lock type mismatch.                                                                                               | Passed |
| VECVE-25 | Trying to extend a lock when the system is in shutdown should fail and revert with an error message indicating that the system is shut down.                                                                                   | Passed |
| VECVE-26 | Shutting down the contract when the caller has elevated permissions should result in the veCVE.isShutdown = 2                                                                                                                  | Passed |
| VECVE-27 | Shutting down the contract when the caller has elevated permissions should result in the cveLocker.isShutdown = 2                                                                                                              | Passed |
| VECVE-28 | Shutting down the contract when the caller has elevated permissions, and the system is not already shut down should never revert unexpectedly.                                                                                 | Passed |
| VECVE-29 | Calling extendLock with continuousLock set to 'true' should set the post extend lock time to CONTINUOUS_LOCK_VALUE.                                                                                                            | Passed |
| VECVE-30 | Calling extendLock for noncontinuous extension in the same epoch should not change the unlock epoch.                                                                                                                           | Passed |
| VECVE-31 | Calling extendLock for noncontinuous extension in a future epoch should increase the unlock time.                                                                                                                              | Passed |
| VECVE-32 | Calling extendLock with correct preconditions should not revert.                                                                                                                                                               | Passed |
| VECVE-33 | Increasing the amount and extending the lock should succeed if the lock is continuous.                                                                                                                                         | Passed |
| VECVE-34 | Increasing the lock amount and extending a continuous lock's validity should succeed, with preLockCVEBalance matching postLockCVEBalance + amount                                                                              | Passed |
| VECVE-35 | Increasing the lock amount and extending a continuous lock's validity should succeed, with preLockVECVEBalance + amount matching postLockVECVEBalance.                                                                         | Passed |
| VECVE-36 | Increasing the amount and extending the lock should succeed if the lock is non-continuous.                                                                                                                                     | Passed |
| VECVE-37 | Increasing the lock amount and extending a non-continuous lock's validity should succeed, with preLockCVEBalance matching postLockCVEBalance + amount                                                                          | Passed |
| VECVE-38 | Increasing the lock amount and extending a non-continuous lock's validity should succeed, with preLockVECVEBalance + amount matching postLockVECVEBalance.                                                                     | Passed |
| VECVE-39 | Processing an expired lock for an existing lock in a shutdown contract should complete successfully                                                                                                                            | Passed |
| VECVE-40 | Processing a lock in a shutdown contract results in decreasing number of user locks.                                                                                                                                           | Passed |
| VECVE-41 | Processing a lock in a shutdown contract results in decreasing user points.                                                                                                                                                    | Passed |
| VECVE-42 | Processing a lock in a shutdown contract results in decreasing chain points                                                                                                                                                    | Passed |
| VECVE-43 | Processing a lock in a shutdown contract results in increasing cve tokens.                                                                                                                                                     | Passed |
| VECVE-44 | Processing a lock in a shutdown contract results in decreasing vecve tokens                                                                                                                                                    | Passed |
| VECVE-45 | Processing an non-continuous lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch.                                                                                    | Passed |
| VECVE-46 | Processing an non-continuous lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch                                                                                       | Passed |
| VECVE-47 | Processing a lock should complete successfully if unlock time is expired.                                                                                                                                                      | Passed |
| VECVE-48 | Processing an expired lock in a shutdown contract results in decreasing user points                                                                                                                                            | Passed |
| VECVE-49 | Processing an expired lock in a shutdown contract results in decreasing chain points                                                                                                                                           | Passed |
| VECVE-50 | Processing a non-continuous expired lock in a shutdown contract results in preChainUnlocksByEpoch - amount being equal to postChainUnlocksByEpoch                                                                              | Passed |
| VECVE-51 | Processing a non-continuous expired lock in a shutdown contract results in preUserUnlocksByEpoch - amount being equal to postUserUnlocksByEpoch                                                                                | Passed |
| VECVE-52 | Processing an expired lock without a relocking option results in decreasing number of user locks                                                                                                                               | Passed |
| VECVE-53 | Processing an expired lock without a relocking option results in increasing cve tokens                                                                                                                                         | Passed |
| VECVE-54 | Processing an expired lock without a relocking option results in decreasing vecve tokens                                                                                                                                       | Passed |


## FuzzVECVE – System Invariants 
| ID        | Property                                                                                        | Result |
| --------- | ----------------------------------------------------------------------------------------------- | ------ |
| S-VECVE-1 | Balance of veCVE must equal to the sum of all non-continuous lock amounts.                      | Passed |
| S-VECVE-2 | User unlocks by epoch should be greater than 0 for all non-continuous locks.                    | Passed |
| S-VECVE-3 | User unlocks by epoch should be 0 for all continuous locks.                                     | Passed |
| S-VECVE-4 | Chain unlocks by epoch should be greater than 0 for all non-continuous locks.                   | Passed |
| S-VECVE-5 | Chain unlocks by epoch should be 0 for all continuous locks.                                    | Passed |
| S-VECVE-6 | The sum of all user unlock epochs for each epoch must be less than or equal to the user points. | Passed |

## So you found a failure? 

Tips and tricks: 
- Use Echidna as the primary fuzzer 
- Medusa works really well to test coverage and to debug the correct behaviour of functions 
- If Echidna or Medusa find an exploit, write a unit test with the same numbers. This can help you sanity check it. Add this unit test to the maintained unit tests. 

## Coverage Limitations 

### VECVE 

- Input ranges on creation of lock does not test full range of input – would benefit from additional coverage 
- Additional stateful functions can be added, including: 
  - Chainpoints 
    - equal to user's (CVE locked as non continuous) + (CVE locked * continuousLock point multiplier)
  - ChainUnlocksByEpoch 
    - The sum of all chainUnlocksByEpoch map values should always be <= chainPoints
    - The sum of all userPoints should be equal to chainPoints
    - The sum of all chainUnlocksByEpoch maps should be equal to the sum of all userUnlocksByEpoch maps.
- `createLockfor` and `increaseAmountAndExtendLockFor`

## Lendtroller 

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
coverage: true  # save coverage
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