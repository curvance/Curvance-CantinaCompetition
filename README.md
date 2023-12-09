<p style="text-align: center;width:100%"> <img src="https://pbs.twimg.com/profile_banners/1445781144125857796/1663645591/1500x500"/></p>

<h1> <img style="text-align: center; height: 18px" src="https://user-images.githubusercontent.com/77558763/148961492-99d86d51-41a3-45a8-9af6-bdc1a85c722b.png"/> curvance contracts</h1>

Main dependencies:
- [Rust](https://www.rust-lang.org/): foundry compiler
  - Confirm you have rust with `rustc --version`
- [Foundry](https://book.getfoundry.sh/getting-started/installation): compile and run the smart contracts on a local development network
  - Confirm you have Foundry with `forge -V`
- [Solhint](https://github.com/protofire/solhint): linter
  - Confirm you have the `solidity` plugin by Juan Blanco in VSCode -- Search settings in VSCode for `Solidity: Linter`, should be set to `solhint`
- [Prettier Plugin Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity): code formatter
  - Confirm you have the `solidity` plugin by Juan Blanco in VSCode -- Search settings in VSCode for `Solidity: Formatter`, should be set to `prettier`

## Setup
1. Copy `.env.sample` and fill it out with your own information
2. Ensure you have `forge` installed, A guide can be found [here](https://book.getfoundry.sh/getting-started/installation)
3. Happy building, all dependencies are gitmodule linked & remapping can be found in `remappings.txt` which should be picked up automatically

## Internal code guidelines
### Smart contract order
1. Types at the top of the contract
2. Constants
3. Storage
4. Events
5. Errors
6. Constructor
7. External
8. Public
9. Internal
10. Private as the end of the contract

### Linting
- Prettier is set to have `printWidth` of 79 however comments sometimes do not take this, but are enforced in code review. Please ensure your commented lines do not exceed 79 characters.

## Foundry tips
### Build & compile
Compile all contracts

```sh
forge build
```

### Run tests
Compile all smart contracts & run all tests in /tests
- To run a specific test use `--match-contract`
- For more details like  console logs add `-vv`
```sh
forge test
```

### Check coverage

Compile all smart contracts and check test coverage

```sh
forge coverage
```

### Execute script
Execute a specific script using forge

```sh
forge script script/<something>.s.sol
```

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
