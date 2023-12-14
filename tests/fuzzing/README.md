# Invariants being Tested 

# FuzzVECVE.sol


| Function                                   | Test Case                                              | Test Purpose                                                                                 | Expected Behaviour                                                                  |
| :----------------------------------------- | :----------------------------------------------------- | :------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------- |
| `create_lock_with_zero_should_fail`        | `amount = 0`                                           | A lock shouldn't be able to be created with 0 amount, it should fail instead.                | Error with `_INVALID_LOCK_SELECTOR`                                                 |
| `create_continuous_lock_when_not_shutdown` | `amount` is within `[1, type(uint32).max]`             | Checks success case for creating a lock. Amount is clamped within the lower and upper bound. | Successful transfer of specified CVE tokens and equivalent minting of VE-CVE tokens |
| `extend_lock_should_fail_if_shutdown`      | `veCVE.isShutdown() = 2`                               | Extension of lock should fail if shutdown is in progress                                     | Error with `_VECVE_SHUTDOWN_SELECTOR`                                               |
| `shutdown_success_if_elevated_permission`  | An elevated permission is available, not yet shut down | The function should successfully shutdown if called by an address with elevated permissions  | Shutdown state successfully set, no error                                           |

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
- # of seconds to run Medusa: 2 minutes 

### Medusa – Cloud 

```bash 
make medusa-cloud
```
Notable differences: 
- # of seconds to run Medusa: 16 hours 


We use [cloudexec](https://github.com/crytic/cloudexec/tree/hotfix) to run this fuzzing suite on the server. As the release has not been cut yet, see below for installation: 
```bash
git clone https://github.com/crytic/cloudexec.git
git checkout hotfix 
make
```
Add the binary above to your PATH and you should be able to run cloudexec after sufficient setup.

Run `cloudexec pull ./output` to pull the most recent corpus runs (note that both Echidna and Medusa corpus runs have been changed to write to this directory).