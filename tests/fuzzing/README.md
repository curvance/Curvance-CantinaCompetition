# Invariants being Tested 

# FuzzVECVE.sol

| Function Name                                                              | Test Case                                                                              | Test Purpose                                                                                                | Expected Behaviour                                                                                                |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `combineAllLocks_should_succeed_to_non_continuous_terminal`                | A mix of continuous and non-continuous locks                                           | Tests the scenario where a user combines all of their locks into a single non-continuous lock               | The combined lock amount matches the total original lock amounts, and user points are correctly adjusted          |
| `processExpiredLock_should_succeed`                                        | Given an existing lock identified by `seed`, in an active contract that isn't shutdown | Tests the successful processing of an expired lock                                                          | The function call to `processExpiredLock` completes successfully                                                  |
| `processExpiredLock_should_fail_if_lock_index_exceeds_length`              | Attempts to process a lock at an index that doesn't exist                              | Tests the failure when trying to process a lock with an index higher than the length of existing locks      | The function reverts with an appropriate error message                                                            |
| `disableContinuousLock_should_succeed_if_lock_exists`                      | Given an existing lock identified by `number`                                          | Tests the successful disabling of a continuous lock                                                         | The function call to `disableContinuousLock` completes successfully                                               |
| `shutdown_success_if_elevated_permission`                                  | The caller has elevated permissions and the contract isn't already shutdown            | Tests the successful shutdown of the contract when the caller has elevated permissions                      | The `isShutdown` function returns `2` for `veCVE` and `cveLocker`, indicating a successful shutdown               |
| `earlyExpireLock_shoud_succeed`                                            | Given an existing lock identified by `seed`                                            | Tests the successful early expiration of a lock                                                             | The function call to `earlyExpireLock` completes successfully                                                     |
| `balance_must_equal_lock_amount_for_non_continuous`                        | The contract has non-continuous locks                                                  | Tests that the balance of `veCVE` for `this` should equal the sum of non-continuous locks' amounts          | The balance of `veCVE` equals the sum of the amounts of non-continuous locks                                      |
| `user_unlock_for_epoch_for_continuous_locks_should_be_zero`                | The contract has continuous locks                                                      | Tests that the user unlocks by epoch should be zero for each epoch of the locks                             | The user unlocks by epoch are zero for all the epochs corresponding to continuous locks                           |
| `chain_unlock_for_epoch_for_continuous_locks_should_be_zero`               | The contract has continuous locks                                                      | Tests that the chain unlocks by epoch should be zero for each epoch of the locks                            | The chain unlocks by epoch are zero for all the epochs corresponding to continuous locks                          |
| `create_lock_when_not_shutdown`                                            | Non-shutdown system and valid lock amount                                              | Tests the successful creation of a lock when the contract is not in shutdown                                | The contract should reflect the new lock amounts correctly                                                        |
| `create_lock_with_less_than_wad_should_fail`                               | Contract not in shutdown and locked amount less than WAD                               | Tests that the creation of a lock with an amount less than WAD fails                                        | The function call to `createLock` should fail                                                                     |
| `create_lock_with_zero_amount_should_fail`                                 | Contract not in shutdown and locked amount is zero                                     | Tests that the creation of a lock with zero amount fails                                                    | The function call to `createLock` should fail                                                                     |
| `extendLock_should_succeed_if_not_shutdown`                                | Non-shutdown system and valid lock index                                               | Tests the successful extension of a lock's validity when contract is not in shutdown                        | Existing unlock time should be increased                                                                          |
| `extend_lock_should_fail_if_already_continuous`                            | Lock is already in continuous state                                                    | Tests that contract correctly restricts extending a continuous lock                                         | The function call to `extendLock` should fail                                                                     |
| `extend_lock_should_fail_if_shutdown`                                      | The contract is in shutdown                                                            | Tests that contract correctly restricts any lock extension during shutdown                                  | The function call to `extendLock` should fail                                                                     |
| `increaseAmountAndExtendLock_should_succeed_if_continuous`                 | Non-shutdown system and valid lock index                                               | Tests the successful extension of a lock's validity and increase in lock amount when lock is continuous     | Existing unlock time should be increased                                                                          |
| `increaseAmountAndExtendLock_should_succeed_if_non_continuous`             | Non-shutdown system and valid lock index                                               | Tests the successful extension of a lock's validity and increase in lock amount when lock is non-continuous | Existing unlock time should be increased                                                                          |
| `combineAllLocks_for_all_continuous_to_continuous_terminal_should_succeed` | All existing locks are continuous                                                      | Tests the successful amalgamation of all locks into a single continuous lock                                | A single continuous lock should exist and user points should remain same                                          |
| `combineAllLocks_non_continuous_to_continuous_terminals_should_succeed`    | Not all existing locks are continuous                                                  | Tests the successful transformation of non-continuous locks to continuous lock terminals                    | An increased value for post-combine user points, balance of veCVE equals the sum of user points and unlock values |


# TestStatefulDeployments.sol


| Function Name                           | Test Case            | Test Purpose                                                                       | Expected Behaviour                                                        |
| --------------------------------------- | -------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `CentralRegistry_is_deployed_and_setup` | (No input variables) | Check whether Central Registry contract has been successfully deployed and setup   | Successful deployment and setup of Central Registry contract              |
| `CentralRegistry_is_setup`              | (No input variables) | Verify if Central Registry contract has been correctly setup with dependencies     | Successful setup of Central Registry with correct dependencies            |
| `CVE_is_deployed`                       | (No input variables) | Ensure the CVE contract has been successfully deployed and setup with dependencies | Successful deployment and setup of CVE contract with correct dependencies |

As per the original table, there are no concrete test cases defined, as these functions directly check the setup of different contracts. The expected behaviour is based on the necessary outcomes for a successful deployment and setup of the contracts.

## So you found a failure? 

Tips and tricks: 
- Use Echidna as the primary fuzzer 
- Medusa works really well to test coverage and to debug the correct behaviour of functions 
- If Echidna or Medusa find an exploit, write a unit test with the same numbers. This can help you sanity check it. Add this unit test to the maintained unit tests. 

## Coverage Limitations 

### VECVE 

- Input ranges on creation of lock does not test full range of input – would benefit from additional coverage 
- increaseAmountAndExtendLock is lacking coverage (or as of currently, fuzzer has not yet reached the state to call)
- Postcondition checks on adding non-continuous locks (i.e: that the lock of the previous values decrease, and new lock values increase)
- Postconditions on additional functions, such as disableContinuousLock, processExpiredLock, early expire 
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
- 


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