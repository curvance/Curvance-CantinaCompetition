# Invariants being Tested 

# FuzzVECVE.sol


Sure, here's the updated table:

| Function Name                                                 | Test Case                                                        | Test Purpose                                                                   | Expected Behaviour                                                      |
| ------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| `create_continuous_lock_when_not_shutdown`                    | `amount` is within `[1, type(uint32).max]`                       | Tests that a new continuous lock can be created when contract is not shutdown  | Successful creation of a continuous lock for non-shutdown contract      |
| `create_lock_with_zero_should_fail`                           | `amount = 0`                                                     | Verifies that lock creation should fail with zero amount                       | Reverted contract call with appropriate error                           |
| `extendLock_should_succeed_if_not_shutdown`                   | `lockIndex` is an existing lock index                            | Checks if a lock can be successfully extended when contract is not shutdown    | Successful lock extension for a non-shutdown contract                   |
| `extend_lock_should_fail_if_already_continuous`               | `lockIndex` points to a continuous lock                          | Verifies that extending a lock should fail if it's already a continuous lock   | Reverted contract call or failed `require` statement with correct error |
| `extend_lock_should_fail_if_shutdown`                         | `lockIndex` is any valid index                                   | Verifies that extending a lock should fail if the contract is shut down        | Reverted contract call or failed `require` statement with correct error |
| `increaseAmountAndExtendLock_should_succeed`                  | `amount` is within `[1, type(uint32).max]`, `lockIndex` is valid | Tests whether the amount of an existing lock can be increased                  | Successful lock amount increase                                         |
| `combineAllLocks_should_succeed`                              | `numLocks > 2`                                                   | Checks if all locks can be successfully combined                               | Successful combination of all locks                                     |
| `processExpiredLock_should_succeed`                           | `lockIndex` is an existing expired lock index                    | Verifies that processing an expired lock should succeed                        | Successful processing of the expired lock                               |
| `processExpiredLock_should_fail_if_lock_index_exceeds_length` | `lockIndex` is out of bounds                                     | Checks if processing an expired lock fails when the lock index is incorrect    | Reverted contract call or failed `require` statement with correct error |
| `disableContinuousLock_should_succeed_if_lock_exists`         | `lockIndex` is an existing lock index                            | Confirms that a continuous lock can be disabled if it exists                   | Successful disabling of continuous lock                                 |
| `shutdown_success_if_elevated_permission`                     | Central Registry has elevated permissions for the contract       | Verifies that shutdown procedure is successful if the contract has permissions | Successful shutdown of contracts                                        |
| `earlyExpireLock_shoud_succeed`                               | `lockIndex` is an existing lock index                            | Tests to ensure that an existing lock can be expired early                     | Successful early expiration of the lock                                 |

# TestStatefulDeployments.sol


| Function Name                           | Test Case            | Test Purpose                                                                       | Expected Behaviour                                                        |
| --------------------------------------- | -------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `CentralRegistry_is_deployed_and_setup` | (No input variables) | Check whether Central Registry contract has been successfully deployed and setup   | Successful deployment and setup of Central Registry contract              |
| `CentralRegistry_is_setup`              | (No input variables) | Verify if Central Registry contract has been correctly setup with dependencies     | Successful setup of Central Registry with correct dependencies            |
| `CVE_is_deployed`                       | (No input variables) | Ensure the CVE contract has been successfully deployed and setup with dependencies | Successful deployment and setup of CVE contract with correct dependencies |

As per the original table, there are no concrete test cases defined, as these functions directly check the setup of different contracts. The expected behaviour is based on the necessary outcomes for a successful deployment and setup of the contracts.

## Installation Requirements

1. Slither 
2. Echidna 
3. Medusa 
4. Foundry 
   
see: 
https://github.com/curvance/curvance-contracts/blob/1ec341b7e3c2408abf3f3853a5a8145fc6bd67c3/cloudexec.toml#L8

## Running Echidna
There are two flavours of the config provided in this code. See below for their differences 

### Echidna – Locally

```bash
make echidna-local 
```

```yaml 
testMode: assertion # run in assertion mode for a quicker test 
coverage: true # saving coverage  
corpusDir: "output/echidna-corpus" # saving coverage in a directory 
cryticArgs: ["--ignore-compile"] # the contracts do not need to be re-compiled 
testMaxGas: 1250000000  # in preparation for future potentially gas-consuming operations 
codeSize: 0xfffffffffff 
testLimit: 500000 # smaller test limit to sanity check quick 
```

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