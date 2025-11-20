# DeFihub Contracts

## TLDR

This repository contains the core smart contracts for the DeFihub v3 protocol - a modular DeFi investment platform built on Solidity.

- **NFTs represent positions** - ERC721 tokens are investment positions, not just collectibles
- **Modular architecture** - Abstract bases provide reusable functionality
- **Multiple strategies/products** - Buy (multi-token purchase), DCA (automated swaps), Liquidity (LP provision), Strategy (meta-composition)
- **Fee distribution** - Fee distribution system rewarding strategists, referrers, and protocol
- **Composability** - Strategy module can combine any products into unified positions
- **Safety** - Input validation, access control, and support for fee-on-transfer tokens

## Directory Structure

```
contracts/
├── abstract/          # Reusable base contracts
├── products/          # Investment product modules
├── libraries/         # Utility libraries
└── helpers/          # Helper contracts
```

## Architecture Overview

The protocol is built on a **position-based ERC721 system** where each NFT represents a user's investment position. All product contracts inherit from base abstracts and implement a standardized three-phase lifecycle:

1. **createPosition** - Mints an NFT and initializes the investment
2. **collectPosition** - Claims rewards/yields without closing the position
3. **closePosition** - Burns the NFT and withdraws all assets

## Abstract Base Contracts (`abstract/`)

These contracts provide modular, reusable functionality that product modules can inherit:

### UsePosition.sol

The foundation of all product modules. Provides:

- **ERC721 token management** - Each position is an NFT with a unique `tokenId`
- **Position lifecycle hooks** - Abstract methods `_createPosition`, `_collectPosition`, `_closePosition` that products must implement
- **Access control** - `onlyPositionOwner` modifier ensures only NFT holders can manage their positions
- **Token handling** - `_pullToken` method that accounts for fee-on-transfer tokens by measuring actual received amounts
- **Amount validation** - `_validateAllocatedAmount` allows up to 0.02% rounding tolerance for handling calculation precision 

**Key structs:**
- `StrategyIdentifier` - Links positions to strategists (`address strategist`, `uint externalRef` for off-chain tracking)
- `FeeReceiver` enum - Defines fee recipient types (STRATEGIST, REFERRER, TREASURY)

### UseReward.sol

Manages accumulated rewards/fees for users, strategists, and treasury:

- **Reward accounting** - `mapping(address => mapping(IERC20 => uint)) public rewards` tracks claimable amounts
- **Batch claiming** - `claimRewards()` allows claiming multiple token types in a single transaction
- **Used by** Liquidity and Strategy modules for distributing performance fees and strategist rewards

### UseReferral.sol

Implements a time-based referral system:

- **Time-limited referrals** - Referral links expire after `referralDuration` (configurable)
- **First-investment tracking** - Only sets referrer on a user's first investment
- **Automatic expiration** - `getReferrer()` returns `address(0)` if the referral has expired
- **Prevents abuse** - Ignores zero address and self-referrals

**How it works:**
1. New users provide a referrer address on their first investment
2. Referral is stored with an expiration timestamp (`block.timestamp + referralDuration`)
3. Referrer earns fees while the referral is active

### UseTreasury.sol

Simple treasury management:

- **Treasury address storage** - Private `_treasury` variable with getter/setter
- **Owner-only updates** - Only contract owner can change treasury address
- **Zero address protection** - Prevents setting treasury to `address(0)`

## Product Modules (`products/`)

Each product is a standalone contract implementing specific DeFi investment strategies. All inherit from `UsePosition` and implement the standard lifecycle.

---

### Buy.sol

**What it does:** A simple multi-token purchase product. Users swap a single input token into multiple output tokens in one transaction, creating a diversified position stored as an NFT.

**How it works:**

1. **Create Phase:**
   - User provides input token and a list of investments (token swaps)
   - Contract pulls input tokens from user (handling fee-on-transfer tokens)
   - Executes each swap using Uniswap Universal Router (via `HubRouter`)
   - Stores resulting token amounts in a `Position[]` array mapped to the tokenId
   - Validates that allocated amounts match received amounts (within 0.02% tolerance)

2. **Collect Phase:**
   - Transfers all tokens from the position to the beneficiary
   - Marks position as claimed to prevent double-claiming
   - Position NFT remains owned by user

3. **Close Phase:**
   - Same as collect - transfers all tokens to beneficiary
   - Burns the position NFT

**Key features:**
- One-time token allocation (no ongoing management)
- Gas-efficient storage (stores only final balances, not swap details)
- Protection against double-collection via `_claimedPositions` mapping

**Use case:** Portfolio diversification - swap stablecoins into a basket of tokens in one transaction.

---

### DollarCostAverage.sol (DCA)

**What it does:** Automated recurring token swaps over time. Users deposit tokens that are automatically swapped at fixed intervals (1 day) into target tokens, implementing a dollar-cost-averaging strategy.

**How it works:**

1. **Pool-based architecture:**
   - Positions are grouped into "pools" identified by `(inputToken, outputToken)` pairs
   - Multiple users' positions in the same pool share swap execution
   - Each pool tracks `performedSwaps`, `nextSwapAmount`, and accumulated swap quotes

2. **Create Phase:**
   - User specifies input amount and number of swaps (e.g., swap 100 tokens over 10 swaps = 10 tokens per swap)
   - Contract converts input to pool's input token (if needed) via HubRouter
   - Calculates `amountPerSwap = inputAmount / swaps` (dust is locked, not tracked - cheaper than accounting for it)
   - Adds `amountPerSwap` to pool's `nextSwapAmount`
   - Schedules position end at `finalSwap = pool.performedSwaps + swaps`
   - Stores position with `swaps`, `finalSwap`, `lastUpdateSwap`, `amountPerSwap`

3. **Swap Execution (by designated swapper):**
   - Swapper calls `swap()` with swap calldata for one or more pools
   - Validates `SWAP_INTERVAL` (1 day) has passed since last swap
   - Takes swap fee (`swapFeeBps`, max 1%) and sends to treasury
   - Executes swap via HubRouter
   - Calculates and stores **swap quote** (output per input) as `accruedSwapQuote[performedSwaps]`
   - Updates pool state: increments `performedSwaps`, deducts ending positions from `nextSwapAmount`

4. **Collect Phase:**
   - Calculates output tokens earned since `lastUpdateSwap` using accumulated swap quotes
   - Formula: `(accruedSwapQuote[currentSwap] - accruedSwapQuote[lastUpdateSwap]) * amountPerSwap / PRECISION`
   - Transfers output tokens to beneficiary
   - Updates `lastUpdateSwap` to current
   - Position continues (NFT not burned)

5. **Close Phase:**
   - Calculates remaining input tokens (unswapped) and accumulated output tokens
   - Returns input tokens: `(finalSwap - performedSwaps) * amountPerSwap`
   - Returns output tokens using same calculation as collect
   - Removes position from pool: deducts from `nextSwapAmount` and `endingPositionDeduction`
   - Burns NFT

**Key features:**
- **Swap quote accumulation** - Efficient accounting using cumulative price ratios
- **Pooled execution** - Gas-efficient: one swap transaction serves multiple users
- **Designated swapper** - Only authorized swapper can trigger swaps (prevents MEV/manipulation)
- **Swap fees** - Protocol earns fee on each swap (max 1%)
- **Flexible withdrawal** - Users can collect yields or close position at any time

**Use case:** DCA strategy - automatically buy ETH with USDC over 30 days (30 swaps), reducing volatility and timing risk.

---

### Liquidity.sol

**What it does:** Uniswap V3 liquidity provision with performance fee sharing. Users provide liquidity to Uniswap V3 pools, and the protocol takes performance fees on yields earned (swap fees from the pool).

**How it works:**

1. **Create Phase:**
   - User provides input token, investments (LP position parameters), strategist info, and performance fee
   - Validates `strategistPerformanceFeeBps` ≤ 15%
   - For each investment:
     - Swaps input token into `token0` and `token1` via HubRouter
     - Approves Uniswap NFT Position Manager
     - Calls `positionManager.mint()` to create Uniswap V3 LP position
     - Receives Uniswap LP NFT (tokenId) and initial liquidity amount
     - Wraps Uniswap position in `DexPosition` struct and stores in protocol position
   - Protocol position NFT represents wrapper around 1+ Uniswap LP positions

2. **Collect Phase (harvest fees without closing):**
   - For each wrapped Uniswap position:
     - Calls `positionManager.collect()` to claim accumulated trading fees
     - Distributes fees using three-way split:
       - **User**: `amount - strategistFee - protocolFee`
       - **Strategist**: `amount * strategistPerformanceFeeBps / 10000` (up to 15%)
       - **Treasury**: `amount * protocolPerformanceFeeBps / 10000` (up to 15%)
     - Transfers user portion to beneficiary immediately
     - Credits strategist and treasury portions to `rewards` mapping (claimable via `UseReward`)
   - Position remains open, liquidity stays in Uniswap pool

3. **Close Phase:**
   - For each wrapped Uniswap position:
     - Collects accumulated fees (same as collect phase)
     - Distributes fees to user/strategist/treasury
     - Calls `positionManager.decreaseLiquidity()` to remove all liquidity from Uniswap
     - Collects withdrawn `token0` and `token1`
     - Transfers all tokens (withdrawn liquidity + fees) to beneficiary
   - Burns protocol position NFT

**Key features:**
- **Multi-position support** - One protocol NFT can wrap multiple Uniswap LP positions
- **Performance fee split** - Three-tier distribution (user/strategist/treasury)
- **Strategist rewards** - Strategy creators earn ongoing fees on positions using their strategy
- **Fee caps** - Prevents excessive performance fees (max 15% for strategist, 15% for protocol)
- **Non-custodial** - User's Uniswap LP NFTs are held by contract but position ownership is clear via protocol NFT

**Use case:** Create a multi-position LP strategy and allow strategists to earn performance fees.

---

### Strategy.sol

**What it does:** A meta-module that composes other product modules. Routes user deposits across multiple product modules (Buy, DCA, Liquidity), handles fee distribution to strategists/referrers/treasury, and supports native ETH deposits.

**How it works:**

1. **Create Phase:**
   - User provides input token/amount, strategy identifier, referrer, and list of module investments
   - **Fee collection first** (upfront fees, not performance-based):
     - Strategist fee: `inputAmount * strategistFeeBps / 10_000` (if strategist specified)
     - Referrer fee: `inputAmount * referrerFeeBps / 10_000` (if valid referrer exists)
     - Protocol fee: `inputAmount * protocolFeeBps / 10_000` (+ referrer fee if no referrer)
     - Max total fees: 1% (`MAX_TOTAL_FEE_BPS = 100`)
     - Fees credited to `rewards` mapping
   - Sets referrer for user (if first investment and valid referrer provided)
   - Remaining amount after fees is distributed to sub-modules:
     - For each investment:
       - Approves sub-module to spend allocated amount
       - Calls `module.createPosition()` with encoded parameters
       - Receives module's tokenId
       - Stores `Position(module, moduleTokenId)` mapping
   - Validates all allocations match remaining amount (within 0.02% tolerance)

2. **Collect Phase:**
   - Receives array of bytes (one per sub-module position)
   - Calls `module.collectPosition()` for each wrapped position
   - Yields go directly to beneficiary (no additional fees)

3. **Close Phase (two variants):**
   - **Regular close:**
     - Calls `module.closePosition()` for each wrapped position
     - Tokens go to beneficiary
   - **Single-token close** (`closePositionSingleToken`):
     - Closes all positions to intermediate contract
     - Swaps all output tokens into single desired output token via HubRouter
     - Enforces minimum output amount (slippage protection)
     - Transfers final output token to beneficiary

**Additional features:**
- **Native ETH support:**
  - `createPositionEth()` - Accepts ETH, wraps to WETH, creates positions
- **ERC20 Permit support:**
  - `createPositionPermit()` - Gasless approval via EIP-2612 permit
- **Referral system:**
  - Inherits `UseReferral` for time-limited referral tracking
  - Referrer earns `referrerFeeBps` on first investment only
- **Recursive prevention:**
  - Blocks Strategy module from calling itself (`InvalidModule` error)

**Key features:**
- **Module composition** - Combine any products (Buy + DCA + Liquidity in one position)
- **Upfront fee distribution** - Strategist and referrer fees taken at creation
- **Referral rewards** - Incentivizes user acquisition
- **Native ETH handling** - Seamless WETH wrapping
- **Flexible exit** - Standard close or swap-to-single-token close

**Use case:** Create a comprehensive strategy that buys some tokens immediately (Buy), DCA into others over time (DCA), and provides liquidity (Liquidity) - all in one transaction, while rewarding the strategy creator and referrer.

---

## Libraries (`libraries/`)

### HubRouter.sol

Wrapper library for Uniswap's Universal Router. Provides simplified interface for executing token swaps:

**Key functions:**
- `execute()` - Swaps ERC20 tokens via Universal Router, returns output amount
- `executeNative()` - Swaps native ETH via Universal Router, returns output amount

**How it works:**
- Measures token balances before/after router call to handle fee-on-transfer tokens
- Returns actual received amount (not nominal swap amount)
- Skips swap if input == output token (returns input amount)

**HubSwap struct:**
```solidity
struct HubSwap {
    IUniversalRouter router;  // Universal Router address
    bytes commands;           // Router commands
    bytes[] inputs;           // Encoded swap parameters
}
```

### TokenArray.sol

Utility library for working with arrays of IERC20 tokens:

- `validateUniqueAndSorted()` - Ensures array is sorted ascending and has no duplicates
- Used by Strategy module's single-token close to validate token arrays

## Helpers (`helpers/`)

### RewardClaimer.sol

Utility contract for batch claiming rewards across multiple modules:

- Allows users to claim rewards from Liquidity and Strategy modules in one transaction
- Reduces gas costs for users with rewards in multiple modules

## Fee System

The protocol implements multiple fee mechanisms depending on the product:

### Strategy Module (Upfront Fees)
- **Protocol fee** (`protocolFeeBps`): Goes to treasury
- **Strategist fee** (`strategistFeeBps`): Goes to strategy creator
- **Referrer fee** (`referrerFeeBps`): Goes to referrer (if valid)
- **Maximum total**: 1% (`MAX_TOTAL_FEE_BPS = 100`)
- **When**: Deducted at position creation

### Liquidity Module (Performance Fees)
- **Protocol performance fee** (`protocolPerformanceFeeBps`): Up to 15%
- **Strategist performance fee** (`strategistPerformanceFeeBps`): Up to 15%
- **When**: Deducted from LP yields (trading fees) when collected/closed

### DCA Module (Swap Fees)
- **Swap fee** (`swapFeeBps`): Up to 1% (`MAX_SWAP_FEE_BPS = 100`)
- **When**: Deducted from each automated swap execution

### Buy Module
- **No fees** - Pure swap execution product

## Security Patterns

### Input Validation
- **Amount validation** - `_validateAllocatedAmount()` ensures allocations match inputs within 0.02% tolerance
- **Fee limits** - All fee types have maximum caps to prevent excessive charges
- **Address validation** - Prevents zero addresses where critical (treasury, referrers)

### Access Control
- **Position ownership** - `onlyPositionOwner` modifier enforces only NFT holder can manage position
- **Admin functions** - Owner-only functions for updating fees, treasury, etc.
- **Designated swapper** - DCA swaps can only be triggered by authorized address

### Reentrancy Protection
- **Checks-Effects-Interactions** pattern followed throughout
- **Balance measurements** - Uses before/after balance checks instead of trusting return values

### Fee-on-Transfer Token Support
- **Actual balance tracking** - `_pullToken()` measures actual received amounts
- **Rounding tolerance** - 0.02% tolerance handles transfer fees and calculation precision

## Integration Points

### External Protocols
- **Uniswap V3 Core** - Liquidity pools
- **Uniswap V3 Periphery** - NFT Position Manager for LP positions
- **Uniswap Universal Router** - Token swaps (via HubRouter wrapper)

### Internal Integrations
- **Strategy → Products** - Strategy module calls other products' `createPosition()`
- **Products → HubRouter** - All products use HubRouter for token swaps
- **Products → UseReward** - Liquidity and Strategy credit rewards for batch claiming

## Position Lifecycle Example

```
1. User calls Strategy.createPosition()
   ├─> Collects upfront fees (strategist/referrer/protocol)
   ├─> Calls Buy.createPosition() with allocation #1
   │   └─> Mints Buy NFT #123
   ├─> Calls DCA.createPosition() with allocation #2
   │   └─> Mints DCA NFT #456
   └─> Calls Liquidity.createPosition() with allocation #3
       └─> Mints Liquidity NFT #789
   └─> Mints Strategy NFT #42 (wraps #123, #456, #789)

2. User calls Strategy.collectPosition(#42)
   ├─> Calls Buy.collectPosition(#123) → sends tokens to user
   ├─> Calls DCA.collectPosition(#456) → sends swapped tokens to user
   └─> Calls Liquidity.collectPosition(#789)
       ├─> Collects LP fees from Uniswap
       ├─> Distributes fees (user/strategist/treasury)
       └─> Sends user portion immediately

3. User calls Strategy.closePosition(#42)
   ├─> Burns Strategy NFT #42
   ├─> Calls Buy.closePosition(#123)
   │   ├─> Burns Buy NFT #123
   │   └─> Sends all tokens to user
   ├─> Calls DCA.closePosition(#456)
   │   ├─> Burns DCA NFT #456
   │   └─> Sends remaining input + accumulated output tokens
   └─> Calls Liquidity.closePosition(#789)
       ├─> Burns Liquidity NFT #789
       ├─> Removes liquidity from Uniswap
       ├─> Collects fees (distributed as above)
       └─> Sends all tokens to user
```
