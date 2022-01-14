<p style="text-align: center;width:100%"> <img src="https://pbs.twimg.com/profile_banners/1445781144125857796/1633536472/1500x500"/></p>

<h1> <img style="text-align: center; height: 18px" src="https://user-images.githubusercontent.com/77558763/148961492-99d86d51-41a3-45a8-9af6-bdc1a85c722b.png"/> curvance contracts</h1>
Main dependencies:

- [Hardhat](https://github.com/nomiclabs/hardhat): compile and run the smart contracts on a local development network
- [TypeChain](https://github.com/ethereum-ts/TypeChain): generate TypeScript types for smart contracts
- [Ethers](https://github.com/ethers-io/ethers.js/): renowned Ethereum library and wallet implementation
- [Waffle](https://github.com/EthWorks/Waffle): tooling for writing comprehensive smart contract tests
- [Solhint](https://github.com/protofire/solhint): linter
- [Solcover](https://github.com/sc-forks/solidity-coverage): code coverage
- [Prettier Plugin Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity): code formatter

## Yarn scripts

### Pre Requisites

Before running any command, you need to create a `.env` file and set a BIP-39 compatible mnemonic as an environment
variable. Follow the example in `.env.example`. If you don't already have a mnemonic, use this [website](https://iancoleman.io/bip39/) to generate one.

Then, proceed with installing dependencies:

```sh
yarn install
```

### Compile

Compile the smart contracts with Hardhat:

```sh
$ yarn compile
```

### TypeChain

Compile the smart contracts and generate TypeChain artifacts:

```sh
$ yarn typechain
```

### Lint Solidity

Lint the Solidity code:

```sh
$ yarn lint:sol
```

### Lint TypeScript

Lint the TypeScript code:

```sh
$ yarn lint:ts
```

### Test

Run the Mocha tests:

```sh
$ yarn test
```

### Coverage

Generate the code coverage report:

```sh
$ yarn coverage
```

### Report Gas

See the gas usage per unit test and average gas per method call:

```sh
$ REPORT_GAS=true yarn test
```

### Clean

Delete the smart contract artifacts, the coverage reports and the Hardhat cache:

```sh
$ yarn clean
```

### Deploy

Deploy the contracts to Hardhat Network:

```sh
$ yarn deploy --greeting "Bonjour, le monde!"
```

## Syntax Highlighting

If you use VSCode, you can enjoy syntax highlighting for your Solidity code via the
[vscode-solidity](https://github.com/juanfranblanco/vscode-solidity) extension. The recommended approach to set the
compiler version is to add the following fields to your VSCode user settings:

```json
{
  "solidity.compileUsingRemoteVersion": "v0.8.4+commit.c7e474f2",
  "solidity.defaultCompiler": "remote"
}
```

## Git Commits

### Linting

See: https://github.com/conventional-changelog/commitlint#what-is-commitlint

### Troubleshoot

Error:

`Error [ERR_UNSUPPORTED_ESM_URL_SCHEME]: Only file and data URLs are supported by the default ESM loader`

Suggestion:

Bump your `node` version to `16.0.0`.

## Code Reviews

Reviews are a very imporant part of our development process. 2 approvals are required to merge a pull request.

For certain topics that come up again and again during review discussions, this document is the source of truth if it covers the topic (e.g. best practices in Solidity).

If you think something needs to be changed in the code please require changes. Often times reviewers just mention something they feel should maybe look different, but they approve anyways. Your input is important and it is not a negative thing to discuss it with the pull request author before merging.

### Assignment

Github will automatically assign 2 developers in round robin manner, counted against to how many pull request reviews
they are allready assigned to.

## Branching strategy

For now we are using a simple `feature` -> `develop` -> `main` branching model.

### Steps for working on a new feature

- Branch feature branch off of `develop`
  - Branch name should be `clickupIssueId-branch-name-based-on-task-title`
- Once your branch is ready, open a pull request and set `develop` as target branch

### Release

For now, admins will merge `develop` with `main` to keep it up to date.

```
git checkout develop
git merge main // we prevent conflicts on main, resolve conflicts on develop
git checkout main
git merge development
```

This process will probably change later on.
