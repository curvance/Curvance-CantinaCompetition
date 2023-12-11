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
corpusDir: "echidna-corpus" # saving coverage in a directory 
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
corpusDir: "echidna-corpus" #save in echidna-corpus directory 
cryticArgs: ["--ignore-compile"] # the contracts do not need to be re-compiled 
```
