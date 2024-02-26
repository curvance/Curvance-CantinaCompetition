<p style="text-align: center;width:100%"> <img src="https://pbs.twimg.com/profile_banners/1445781144125857796/1663645591/1500x500"/></p>

<h1> <img style="text-align: center; height: 18px" src="https://user-images.githubusercontent.com/77558763/148961492-99d86d51-41a3-45a8-9af6-bdc1a85c722b.png"/> Curvance</h1>

## Curvance at a glance

Curvance is a cross-chain money market for yield bearing assets. Maximize yield while leveraging the full value of your assets. Curvance simplifies DeFi, with a modular system capable of creating complex strategies for users in a single click.

Curvance operates as a hybrid model between a yield optimizer and a cross-margin money market. This model has various characteristics atypical for incumbent money markets such as:
- Collateral deposits and debt deposits receive two different types of tokens, collateral tokens (cTokens) and debt tokens (dTokens). 
- Rehypothecation has been removed. This allows for the support of long-tail assets which, if borrowable, could introduce systemic risk to DeFi.
- "Collateral Posting", by introducing a hybrid model, users can yield farm an unlimited amount of assets, but, to leverage the corresponding money market, the collateral must be "posted", like a perpetual exchange. Collateral posting has restrictions on the total amount of exogenous risk allowed to be introduced into the system.
- Dynamic Interest Rates with interest rate decay, vertex slope can be adjusted upward or downward based on utilization similar to kashi, however, a new continuous negative decay rate is applied every cycle when interest rates slope is elevated.
- Dynamic liquidation engine allows for more nuanced position management inside the system. Introduces a sliding scale of liquidation between light soft liquidations and aggressive hard liquidations.
- Bad debt socialization, when a user's debt is greater than their collateral assets, the entire user's account can be liquidated with lenders paying any collateral shortfall.
- Crosschain gauge system, introducing of gauge system allowing reward streaming to collateral depositors and lenders. With the ability to configure by token and no limit on the number of different token rewards streamed.
- Delegated actions, ability to delegate user actions to any address, allowing for support for things like limit orders, DCA, take profit, crosschain borrowing, crosschain lending. Some of these are built already in this repo, others are not.

[Documentation Link](https://docs.curvance.com/)


### Money Market System

There are two types of tokens inside Curvance:
Collateral tokens, aka cTokens that can be posted as collateral. Debt tokens, aka dTokens that can be lent out to cToken depositors. Unique to Curvance, rehypothecation of collateral token deposits is disabled, this decision was made to allow for vastly improved market risk modeling and the expansion of supportable assets to nearly any erc20 in existence. 

All management of both cTokens and dTokens actions are managed by the Market Manager. These tokens are collectively referred to as Market Tokens, or mTokens. All cTokens and dTokens are mTokens but, not all cTokens are dTokens, and vice versa. 

Curvance offers the ability to store unlimited collateral inside cToken contracts while restricting the scale of exogenous risk. Every collateral asset as a "Collateral Cap", measured in shares. As collateral is posted, the `collateralPosted` invariant increases, and is compared to `collateralCaps`. By measuring collateral posted in shares, this allows collateral caps to grow proportionally with any auto compounding mechanism strategy attached to the token.

It is important to note that, in theory, collateral caps can be decreased below current market collateral posted levels. This would restrict the addition of new exogenous risk being added to the system, but will not result in forced unwinding of user positions.

Curvance also employs a 20-minute minimum duration of posting of cToken collateral, and lending of dTokens. This restriction improves the security model of Curvance and allows for more mature interest rate models. 

Additionally, a new "Dynamic Liquidation Engine" or DLE allows for more nuanced position management inside the system. The DLE facilitates aggressive asset support and elevated collateralization ratios paired with reduced base liquidation penalties. In periods of low volatility, users will experience soft liquidations. But, when volatility is elevated, users may experience more aggressive or complete liquidation of positions.

Bad debt is minimized via a "Bad Debt Socialization" system. When a user's debt is greater than their collateral assets, the entire user's account can be liquidated with lenders paying any collateral shortfall.

#### Collateral Tokens

Curvance's cTokens are ERC4626 compliant. However, they follow their own design flow modifying underlying mechanisms such as totalAssets following a vesting mechanism in compounding vaults but a direct conversion in basic or "primitive" vaults.

The "cToken" employs two different methods of engaging with the Curvance protocol. Users can deposit an unlimited amount of assets, which may or may not benefit from some form of auto compounded yield.

Users can at any time, choose to "post" their cTokens as collateral inside the Curvance Protocol, unlocking their ability to borrow against these assets. Posting collateral carries restrictions, not all assets inside Curvance can be collateralized, and if they can, they have a "Collateral Cap" which restricts the total amount of exogeneous risk introduced by each asset into the system. Rehypothecation of collateral assets has also been removed from the system, reducing the likelihood of introducing systematic risk to the broad DeFi landscape.

These caps can be updated as needed by the DAO and should be configured based on "sticky" onchain liquidity in the corresponding asset. 

The vaults can have their compounding, minting, or redemption functionality paused. Modifying the maximum mint, deposit, withdrawal, or redemptions possible.
     
"Safe" versions of functions have been added that introduce additional reentry and update protection logic to minimize risks when integrating Curvance into external protocols.

#### Debt Tokens

Curvance's dTokens are ERC20 compliant with a close relation to ERC4626. However, they follow their own design flow, without an inherited base contract. This is done intentionally, to maximize security in an age of rapidly developing security attack vectors.

The "dToken" employs a share/asset structure with slightly different configuration, and terminology (to prevent confusion). The variable terms "tokens", and "amount" are used to refer to dTokens values, and underlying asset values. When you see "Tokens" that is associated with dTokens, when you see "amount" that is associated with underlying assets.

Users who have active positions inside a dToken are referred to as accounts. For actions that can be performed by an external party, that will not result in active positions for themselves, more general terms are used such as "Liquidator", "Minter", or "Payer".

"Safe" versions of functions have been added that introduce additional reentry and update protection logic to minimize risks when integrating Curvance into external protocols.


### Crosschain Technology

Curvance was built from the ground up with crosschain in mind. Similar to many other protocols, the native token, CVE is multichain. However, so is everything else. Things such as gauge emissions, fee distributions, voting escrow system, borrowing, lending, are built to scale to many different chains. Currently, all listed functions are built excluding crosschain lending routing in the current codebase.

Curvance has two core contracts to manage crosschain actions:

#### Protocol Messaging Hub

The Protocol Messaging Hub acts as a unified hub for sending messages crosschain. Various actions can be taken such as managing Gauge Emissions offchain -> onchain porting, veCVE token locking data, moving protocol fees, bridging CVE, moving a veCVE lock crosschain, etc. Native gas tokens are stored inside the contract to pay for all crosschain actions. 

#### Fee Accumulator

The Fee Accumulator acts as a unified hub for collecting and transforming fees collected and their preparation for delivery to Curvance DAO users. Currently, fees can be swapped via offchain solver integrations such as 1Inch. An alternative model of permissionless dutch auctions such as the work seen by Uniswap/Euler could be used. However, A/B testing may provide greater insight into the superior model.

Fees can be marked for OTC which will allow the Curvance DAO to purchase them, at fair market value. The Fee accumulator also works in collaboration with the Protocol Messaging Hub to manage system information and fees. Epoch fee distributions are distributed once a single chain has recorded fees accumulated and tokens locked across
all supported chains inside the Curvance Protocol system.

These fees are distributed pro-rata based on the under of locked veCVE tokens on each chain, see "CVELocker.sol" for more information on this.

#### CVE Locker

The CVELocker acts a unified interface for distributing rewards to Curvance DAO users. This system works in collaboration with the VeCVE smart contract. Rewards are distributed biweekly and pile up for each user, allowing them to claim rewards whenever they want. Rewards can be routed directly into other tokens. CVE can be directly routed to; other tokens can be routed into through the delegation system.

Rewards are distributed pro-rata to each chain's CVE locker every two weeks. Fees are moved to some unified chain (can change) along with information corresponding to the number of veCVE locked on a chain. This means, for example, if 10 million reward tokens are to be distributed during an epoch that had 100 million veCVE locked, every user would receive 0.1 reward tokens for each veCVE they had locked during that period. This creates a direct incentive for chains to provide exogenous rewards to Curvance DAO users to move their locks over to their chain, increases the rewards to be distributed on that chain.

Currently rewards/fees are distributed as USDC and are moved through either Circle's CCTP or Wormhole's automatic relayer, other solutions may also be integrated to facilitate a wider range of chain support. Such as routing a distributed reward token into a chain specific stablecoin after a Wormhole message is delivered.


### Tokens

#### CVE

CVE is the native token of Curvance Protocol. It is natively Multichain and can be time locked in a voting escrow position, in exchange for veCVE, which can be used to direct gauge system emissions through offchain voting, and receives protocol fees via the CVE locker. CVE can be received as emissions through the protocol gauge system (more on this below), these emissions can be claimed directly as liquid CVE or can be locked in a voting escrow position, with a multiplier applied to these emissions.

#### VeCVE

The veCVE token uses concepts of voting escrow common in Defi, with several transformative changes.

These changes include:
- Single choice lock duration (1 year):
  This change was made to allow for a unified point system that can be managed across an infinite number of chains, as well as standardizing the rewards received by DAO participants.

- Removal of inflationary rewards:
  A popular system to incentivize people to lock tokens is inflationary rewards, these have been removed to standardize the incentives with users with creating disproportionate rewards for being "early". The goal is a continuous system that is just as attractive in year 15 as it is on Day 1.

- Offchain Voting: 
  By moving from an onchain voting mechanism we minimize expenses to users and can aggregate votes across all chains at the same time, via calling getVotes() on each chain for a user.

- Continuous Lock mode:
  A mode that every lock can be set to that eliminates the need to continually relock voting escrow positions, minimizing friction for users. Also comes with a bonus to system fees and DAO voting power to give a boost to users who have opted for longer term duration risk. Continuous lock mode can be turned on or off at any time. When shutting off continuous lock mode, a lock becomes a natural 1 year duration lock.

- Multichain fees:
  This is talked about in greater detail inside "CVELocker.sol", system fees are distributed pro-rata across all chains rather than isolated chain fee distributions.

- Multichain locks:
  A voting escrow lock can be moved from any chain to any chain inside the Curvance Protocol system. The nature of multichain fees allows for chains themselves to participate in incentive markets in attracting Curvance DAO members to migrate their locks on to their chain, attracting more fees, and as a result, volume (in theory).

- Early Expiry optionality:
  Voting escrow locks introduce duration risk to participants, some of which may want to opt out of due to exogenous circumstances. Because of this, veCVE introducing the option to expire a voting escrow lock early, in exchange, a heavy penalty to the lock's CVE deposit is slashed and sent to the DAO. Providing Curvance DAO additional resources to develop and improve Curvance protocol.

- Combining Locks:
  Users also have the option to combine all their locks into a single fresh lock. This allows for consolidation, and improvement in future transaction execution quality (lower gas costs) when managing their voting escrow position(s). Combine locks can theoretically temporarily be blocked is an epoch has rolled over and has not been delivered to the chain due to runtime invariant checks, this does not introduce any exploitable attack vector.

- Point system (yay points):
  Rather than directly looking at votes or a user's veCVE balance, a points system is introduced to eliminate the need for a "kicking" system. A user's points are maintained inside a points checkpoint value, and a dynamic mapping that monitors at what epoch a user's points will unlock due to voting escrow lock expiry. Theoretically this checkpoint value can become out of sync with chainwide system if a user lets their rewards pile up. This can result in a user's checkpointed points becoming too high when examined directly, but does not introduce any exploitable vector since the user's checkpoint will be updated as they step through each reward epoch. 


### Gauge System
#### Gauge Pool

A Curvance Gauge Pool manages rewards associated with a particular Market Manager. Tokens are not actually "deposited" inside the Gauge Pool, but rather information is documented. This creates an incredibly efficient method of measuring and distributing rewards as no secondary deposit/withdrawal execution is required by users utilizing Curvance Protocol.

A Gauge Pool is built to support an infinite number of rewards in any supported asset. The base level of CVE gauge emissions are distributed through a markets corresponding gauge pool. CVE emissions can be claimed directly, or locked in a 1 year voting escrow position for an additional reward boost. This mechanism was built to better align the duration exposure between Curvance users and the Curvance DAO. The Curvance DAO has a long time horizon, and users who align with that time horizon should be rewarded more greatly than users with a short time horizon, which has a duration mismatch between parties. Additional reward tokens can be streamed to users through our "Partner Gauges" these act as additional reward layers on top of the base CVE reward system. This allows protocols or chains to directly incentivize their ecosystem without building any additional technology on top. The partner gauge system works for any token without writing any additional code.

Gauge rewards, and by extension the Partner Gauges, can distribute rewards to collateral depositors, or lenders, in a market. Borrowers intentionally do not have the ability to receive rewards as this could create looped delta hedged strategies that do not add value to the Curvance Protocol to receive essentially risk free rewards.

The introduction of the ability to incentivize lenders creates an opportunity not only for ecosystem to create attractive terms to lend their ecosystem tokens. But to allow Curvance collateral depositors the ability to incentivize external parties to permissionlessly lend to them. This could, in theory, reduce the interest rate that borrowers pay by attractive additional lenders to their market of course, potentially minimizing their net expenses borrowing inside a particular market.


### Enshrined Actions

Supplemental tooling has been built to enshrine flexible actions inside Curvance. Things such as zapping and native leverage are supported through protocol zappers and the position folding contract.


### Blast Native Contracts

Supplemental contracts have been built for deployment on the L2 Blast. These contracts are developed to manage native yield for the chain and will not be deployed on any other chains. Blast Native mToken (c & d tokens) contracts will not be deployed as is, and are intended to be overridden for asset specific implementations.


## Contest Specific Information
### Areas in scope

The "contracts" folder contains all the smart contracts you will be auditing, excluding:
- mocks
- libraries/external
- interfaces/external

Two solady contracts developed by Vectorized have been included in the audit as we are huge advocates for highly optimized versions of common contract formats and would like to see these fully audited. This means the partial FixedPointMathLib contract, and ERC4626 contracts inside the library folder are intentionally included, and are considered in scope.


### Areas considered out of scope:

**Issues related to swapperlib zapper calls lack of arbitrary calldata validation will be considered out of scope**, the plan is to consolidate swapper and zapper actions being combined into swapper only actions, with dedicated integrations coded for zapping actions. Secondarily, two versions of swapperlib.swap will be written, swapSafe and swapUnsafe. SwapSafe will be used by third party integrations such as fee accumulator, and have additional slippage checks. SwapUnsafe will be used by user integrations such as zapper contracts where the caller is delivering the calldata themselves, and will set their own slippage. As a result, **issues related to compromising of third party systems allowing unlimited slippage are considered out of scope**.

Locked token data actions are intended to be moved over to Wormhole's CCQ prior to mainnet deployment. At this time, **payload/MessageType configuration + calldata encoding/decoding are not production ready, these issues will be considered out of scope.** This refers to aforementioned code in FeeAccumulator, ProtocolMessagingHub, OneBalanceFeeManager (likely to be depreciated), FeeTokenBridgingHub. All other issues inside these contracts will be considered in scope.

**Issues related to Redstone Core oracle adaptor not working due to msg.data not be attached through contract calls will be considered out of scope.** Alternative contract versions will be made for mTokens and Market Manager with extra parameters slots for pull oracles such as Pyth and Redstone Core.

**Issues related to _sendFeeToken() in FeeTokenBridgingHub potentially being configured to send to Polygon** via CCTP bridge preventing receiveWormhomeMessages() from being called and blocking OneBalance Fees will be considered out of scope.

**Temporary failure of VeCVE's combineAllLocks where an epoch has not been delivered is considered out of scope.** A 12 hour blackout period will be added before and after the start of an epoch, and if somehow epochs have not been delivered in 12 hours, state changing actions such as combineAllLocks will be blocked similar to if the VeCVE contract were shutdown. This will honor the runtime invariant check and will be added along with the payload/MessageType + calldata encoding/decoding consolidation outlined above.

Contract sizing of Market Manager and VeCVE currently require the optimizer to be deployed due to contract size above the Spurious Dragon fork restriction. Each contract will likely be consolidated and potentially downsized prior to launch. So, any **issues around potential failure of deployment due to contract size for Market Manager or VeCVE will be considered out of scope.**

There is inherent trust for particular integration contract owners, i.e. if Chainlink multisig rugs, that oracle adaptor could become malicious. So we're looking directly at unprivileged ways to exploit integrations. **Potential issues related to complete compromising of an infrastructual partner are considered out of scope.**

### Technical rollout strategy

Curvance will be deployed in waves with initial support on a minimum of 6 chains day one. The initial launch will be done with CVE out of circulation, with the gauge system off. This will be done by setting the genesisEpoch exactly 8 weeks from the start of the initial launch ("The Beta"). Once beta concludes CVE initial distribution recipients will have a few days to choose to lock their tokens to participate in the first epoch of rewards. Epochs will take place every 2 weeks with the fee accumulator/protocol messaging hub/CTokenCompounding functions managed by Gelato Network. These function calls will be funded by USDC deposited into OneBalance on Polygon PoS, either via OneBalanceFeeManager (or by Curvance DAO if this contract is depreciated). Gelato will trigger gauge emission data porting on the conclusion of each Snapshot Gauge Voting proposal, with Fee Accumulator and CTokenCompounding calls driven by fees accumulated/owned by the corresponding contracts. The primary distribution of USDC for CVE Locker rewards will be via Circle's CCTP via Wormhole's automatic relayer. The alternative of using Wormhole's native bridge is may be used but will be implemented on a case-by-case basis for each chain.   

### Attack Vectors

Curvance's main attack vectors are mainly around crosschain action staleness, Money Market invariant manipulation, VeCVE points system, and Gauge System edge cases.

- Are there bugs/exploits available to whether fee are transferred but lock data is not transferred somehow (1 message fails, other succeeds).
- Are there bugs if multiple epochs of rewards/information (gauge emissions) have not been delivered.
- Does a user allowing many epochs to pile up create opportunities for them to exploit their reward allocation to CVE locker.
- Is there a way for users to manipulate their userNextClaimIndex invariant to claim an epoch or epochs multiple times from the CVE Locker.
- Is there a way to manipulate totalBorrows/debtBalanceCached in dToken to drain a market.
- Is there a way to manipulate _totalAssets in cTokenBase (and other cToken contracts) to drain a vault.
- What happens if a sequencer for a network goes down and a crosschain message cannot be delivered.
- Does starting Curvance and having user deposits before the genesis epoch create issues for depositors.
- Is there a way to manipulate price feeds in any of the oracle adaptors and bypass the circuit breaker logic, or to use circuit breaker logic to your advantage with some DOS.
- Is there a way to bypass the 20 minute minimum on redemption/loan repayment, opening Curvance up to flashloans or other single block attack vectors.
- Can the dynamic interest rate model be meaningfully exploited by depositing or withdrawing funds aggressively around period updates.
- Can veCVE points/unlock workflow be manipulated/exploited through various actions either at once, or over several years.
- Is there a way to bypass the swapperlib calldata validation and potentially inject malicious code on an approved swapper contract.
- Can the activePosition invariant be broken inside MarketManager with the native opening/closing logic.
- Are any external dependencies improperly implemented? Are we opening ourselves up to any multisystem exploit (e.g. they manipulate something inside an external protocol, allowing theft of Curvance user assets due to improper accounting on our end).
- Can liquidateAccount be used to avoid debt obligations, or worse, steal Curvance collateral or debt assets.
- Is there a meaningful way to bypass collateral caps on assets inside a Curvance Market, not via governance changes grandfathering in users, but directly bypassing invariant checks.
- Can the dual-bridge system be exploited to cause corruption of state across the multi-chain?
- Can the reward accounting ever fail to satisfy a user's legimitate withdrawal?
- Is the CToken underlying ever not 100% liquid?
- Is there a way to liquidate more than expected of a certain user?
- Is all arithmetic always rounding in directions to benefit the protocol?
- Are there economical attacks on the liquidation curve that could make liquidation unattractive for liquidators to spur bad debt?
- Are there cross-contract reentrancy attacks on the CVELocker / VeCVE pair ?
- Are there locations where market listing checks / market pause / health checks / access checks are forgotten?
- Are there contracts which through reasonable use could suffer from stuck funds?
- Could cross chain messaging fail due to misaccuracies in bridging fees?

### Tests

Attached in this repo you will find just over 1,000 tests in categories such as unit tests/integration tests/stateless fuzzing tests. Additionally, you will also find a substantial stateful fuzzing testing harness with just over 200 invariants tests. This was built in collaboration with Trail of Bits and covers VeCVE and most of the Curvance Money Markets. You can also find an attached readme in the fuzzing suite folder covering running the harness locally or in the cloud. Other tests can be ran simply via forge tests. Additional information on running the test suite can be found in the repo readme. 

### Proof of Concepts

As part of the test suite inside Curvance, you will find many testing base contracts that set up Curvance and test various functionality. These are perfect to utilize when you want to work on a proof on concept for a bug. Feel free to mess around with test suite and to modify the testing deployments for whichever scenarios you would like to explore.