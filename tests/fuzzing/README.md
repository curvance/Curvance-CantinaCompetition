# Invariants being Tested 

# FuzzVECVE.sol

| Invariant ID | Function Name                            | Invariant                                                                               | Input Ranges                                                     |
| ------------ | ---------------------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 1            | create_lock_with_zero_should_fail        | Lock creation should not accept zero amount                                             | Amount: 0                                                        |
| 2            | create_continuous_lock_when_not_shutdown | Continuous lock can be created if not shutdown                                          | Amount: clamp beween 1 and `type(uint32).max`                    |
| 3            | extend_lock_should_fail_if_shutdown      | Lock extension should fail if already shutdown                                          | `lockIndex` not specified, ContinuousLock: Depends on test setup |
| 4            | shutdown_success_if_elevated_permission  | Shutdown should succeed if operation is executed by an entity with elevated permissions | Not applicable. No input variables in function                   |

# TestStatefulDeployments.sol

| Invariant ID | Function Name                         | Invariant                                                                       | Input Ranges                                   |
| ------------ | ------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------- |
| 5            | CentralRegistry_is_deployed_and_setup | Central Registry contract has been successfully deployed and setup              | Not applicable. No input variables in function |
| 6            | CentralRegistry_is_setup              | Central Registry contract has been successfully setup with correct dependencies | Not applicable. No input variables in function |
| 7            | CVE_is_deployed                       | CVE contract has been successfully deployed and setup with correct dependencies | Not applicable. No input variables in function |

Each test is designed to check the post-deployment state of the Central Registry and CVE contracts. The invariants are determined by the conditions set in the `assertWithMsg` statements, similar to the previous explanation.

## Installation Requirements

1. Slither 
2. Echidna 
3. Medusa 
4. Foundry 
   
see: 
https://github.com/curvance/curvance-contracts/blob/1ec341b7e3c2408abf3f3853a5a8145fc6bd67c3/cloudexec.toml#L8

## Running 
There are two flavours of the config provided in this code. See below for their differences 

### Local 
Run `make echidna-local`
```yaml 
testMode: assertion # run in assertion mode for a quicker test 
coverage: true # saving coverage  
corpusDir: "output/echidna-corpus" # saving coverage in a directory 
cryticArgs: ["--ignore-compile"] # the contracts do not need to be re-compiled 
testMaxGas: 1250000000  # in preparation for future potentially gas-consuming operations 
codeSize: 0xfffffffffff 
testLimit: 500000 # smaller test limit to sanity check quick 
```

### Cloud 
Run `make echidna-cloud`
```yaml
testMode: exploration # run in exploration mode to increase coverage 
testLimit: 10000000 # number may change, but will increase according to coverage   
coverage: true  # save coverage
corpusDir: "output/echidna-corpus" #save in echidna-corpus directory 
cryticArgs: ["--ignore-compile"] # the contracts do not need to be re-compiled 
```

We use [cloudexec](https://github.com/crytic/cloudexec/tree/hotfix) to run this fuzzing suite on the server. As the release has not been cut yet, see below for installation: 
```bash
git clone https://github.com/crytic/cloudexec.git
git checkout hotfix 
make
```
Add the binary above to your PATH and you should be able to run cloudexec after sufficient setup.

Run `cloudexec pull ./output` to pull the most recent corpus runs (note that both Echidna and Medusa corpus runs have been changed to write to this directory).