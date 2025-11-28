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
└── helpers/           # Helper contracts
```

## Architecture Overview

The protocol is built on a **position-based ERC721 system** where each NFT represents a user's investment position. All product contracts inherit from base abstracts and implement a standardized three-phase lifecycle:

1. **createPosition** - Mints an NFT and initializes the investment
2. **collectPosition** - Claims rewards/yields without closing the position
3. **closePosition** - Burns the NFT and withdraws all assets

## Abstract Base Contracts (`abstract/`)

These contracts provide modular, reusable functionality that product modules can inherit.

### UsePosition.sol

The foundation of all product modules. Provides the ERC721 token management system where each position is represented by an NFT. Implements access control to ensure only NFT holders can manage their positions, and defines abstract lifecycle hooks that products must implement.

Includes helper methods for pulling tokens from users that account for fee-on-transfer tokens by measuring actual received amounts. Amount validation allows up to 0.02% rounding tolerance to handle calculation precision.

### UseReward.sol

Manages accumulated rewards and fees for users, strategists, and the treasury. Tracks claimable amounts for each address per token and provides batch claiming functionality, allowing users to claim multiple token types in a single transaction.

Used by Liquidity and Strategy modules to distribute performance fees and strategist rewards efficiently.

### UseReferral.sol

Implements a time-based referral system where referral links expire after a configurable duration. Only tracks referrals on a user's first investment and automatically returns no referrer after expiration. Prevents abuse by ignoring zero addresses and self-referrals.

### UseTreasury.sol

Simple treasury management with owner-controlled updates and zero address protection.

## Product Modules (`products/`)

Each product is a standalone contract implementing specific DeFi investment strategies. All inherit from `UsePosition` and implement the standard lifecycle.

---

### Buy.sol

**What it does:** A simple multi-token purchase product. Users swap a single input token into multiple output tokens in one transaction, creating a diversified position stored as an NFT.

**How it works:**

1. **Create Phase:**
   - Accepts input token and list of desired token swaps
   - Pulls input tokens from user, handling fee-on-transfer tokens correctly
   - Executes each swap using Uniswap Universal Router
   - Stores resulting token balances in the position
   - Validates allocated amounts match received amounts within tolerance

2. **Collect Phase:**
   - Transfers all tokens from the position to beneficiary
   - Marks position as claimed to prevent double-claiming
   - NFT remains with the user

3. **Close Phase:**
   - Transfers all remaining tokens to beneficiary
   - Burns the position NFT

**Key features:**
- One-time token allocation with no ongoing management
- Gas-efficient storage of final balances only
- Protection against double-collection

**Use case:** Portfolio diversification - swap stablecoins into a basket of tokens in one transaction.

---

### DollarCostAverage.sol (DCA)

**What it does:** Automated recurring token swaps over time. Users deposit tokens that are automatically swapped at fixed 1-day intervals into target tokens, implementing a dollar-cost-averaging strategy.

**How it works:**

The contract uses a **pool-based architecture** where multiple users' positions in the same token pair share swap execution:

1. **Create Phase:**
   - User specifies how many swaps they want to execute (e.g., 10 swaps over 10 days)
   - Contract calculates per-swap amount by dividing total by number of swaps
   - Small dust amounts from division are locked rather than tracked (more gas-efficient)
   - Position joins a pool for the specific input/output token pair
   - Position is scheduled to end after its specified number of swaps

2. **Swap Execution:**
   - Designated swapper executes swaps for entire pools (not individual positions)
   - Can only execute once per 1-day interval per pool
   - Takes configurable swap fee (max 1%) sent to treasury
   - Records swap rate (how much output per input) for accounting
   - Updates pool state to reflect completed swap

3. **Collect Phase:**
   - Calculates output tokens earned based on swap rates since last collection
   - Uses accumulated swap rate accounting for gas-efficient calculation
   - Transfers output tokens to beneficiary
   - Updates last collection point
   - Position continues running

4. **Close Phase:**
   - Calculates remaining unswapped input tokens
   - Calculates accumulated output tokens since last collection
   - Returns both to beneficiary
   - Removes position from pool
   - Burns NFT

**Key features:**
- Pooled execution where one swap serves multiple users
- Designated swapper prevents MEV and manipulation
- Efficient accounting using cumulative swap rates
- Flexible withdrawal - collect yields or close anytime
- Protocol earns fees on each swap

**Use case:** DCA strategy - automatically buy ETH with USDC over 30 days, reducing timing and volatility risks.

---

### Liquidity.sol

**What it does:** Uniswap V3 liquidity provision with performance fee sharing. Users provide liquidity to earn from trading fees.

**How it works:**

1. **Create Phase:**
   - User provides input token and liquidity position parameters
   - Validates performance fees are within limits (max 15% each for strategist and protocol)
   - For each desired liquidity position:
     - Swaps input token into the two tokens needed for the pool
     - Creates Uniswap V3 LP position via their Position Manager
     - Receives Uniswap's LP NFT and wraps it in protocol position
   - One protocol NFT can wrap multiple Uniswap LP positions

2. **Collect Phase (harvest fees without closing):**
   - For each wrapped Uniswap position:
     - Claims accumulated trading fees from Uniswap
     - Splits fees three ways:
       - User receives majority portion immediately
       - Strategist receives performance fee (0-15%, set at creation)
       - Treasury receives protocol performance fee (0-15%, configurable)
     - Strategist and treasury portions go to rewards system for batch claiming
   - Liquidity remains in Uniswap pools

3. **Close Phase:**
   - Claims any accumulated fees (distributed as above)
   - Removes all liquidity from Uniswap positions
   - Transfers all tokens (withdrawn liquidity + fees) to beneficiary
   - Burns protocol position NFT

**Key features:**
- Multi-position support - one NFT wraps multiple Uniswap LP positions
- Strategy creators earn ongoing performance fees
- Fee caps prevent excessive charges
- Non-custodial - clear ownership via protocol NFT

**Use case:** Create a multi-position LP strategy and allow strategists to earn performance fees.

---

### Strategy.sol

**What it does:** A meta-module that composes other product modules. Routes user deposits across multiple products (Buy, DCA, Liquidity), handles deposit fee distribution, and supports native ETH deposits.

**How it works:**

1. **Create Phase:**
   - User provides input token/amount and list of investments across different product modules
   - **Deposit fee collection:**
     - Takes strategist, referrer, and protocol fees from input (max 1% total)
     - Fees are credited to rewards system for claiming
     - If no referrer, protocol receives the referrer portion too
   - Sets up referral relationship if this is user's first investment
   - Distributes remaining amount to specified product modules:
     - Allocates portion to each sub-module
     - Creates position in each sub-module
     - Tracks which module NFTs are owned by this strategy position
   - Validates all allocations match available amount
   - Prevents recursive calls (Strategy cannot invest in itself)

2. **Collect Phase:**
   - Forwards collect calls to each wrapped module position
   - No additional fees taken
   - Yields go directly to beneficiary

3. **Close Phase:**
   - **Regular close:** Forwards close calls to all wrapped positions
   - **Single-token close:** Special mode that:
     - Closes all positions
     - Swaps all received tokens into one desired output token
     - Enforces minimum output for slippage protection
     - Transfers single output token to beneficiary

**Additional features:**
- Native ETH support via automatic WETH wrapping
- Gasless approvals via ERC20 permit signatures
- Referral system for user acquisition incentives
- Recursive call prevention

**Key features:**
- Module composition - combine any products in one position
- Deposit fee distribution to strategists and referrers
- Referral rewards incentivize user acquisition
- Native ETH handling
- Flexible exit with optional consolidation to single token

**Use case:** Create comprehensive strategy that buys some tokens immediately, DCA into others over time, and provides liquidity, all in one transaction, while rewarding strategy creator and referrer.

---

## Libraries (`libraries/`)

### HubRouter.sol

Wrapper library for Uniswap's Universal Router. Provides simplified interface for token swaps with built-in balance tracking to handle fee-on-transfer tokens correctly. Returns actual received amounts rather than nominal swap amounts.

### TokenArray.sol

Utility library for validating token arrays are sorted and unique, used by Strategy module's single-token close functionality.

## Helpers (`helpers/`)

### RewardClaimer.sol

Batch claiming utility that allows users to claim rewards from multiple modules in one transaction, simplifying the process and reducing gas costs.

## Fee System

The protocol implements different fee mechanisms depending on the product:

### Strategy Module - Deposit Fees
- Protocol, strategist, and referrer fees deducted at position creation
- Maximum 1% total across all three fee types
- Immediate distribution to rewards system

### Liquidity Module - Performance Fees
- Protocol and strategist performance fees (up to 15% each)
- Deducted from LP yields when collected/closed
- Rewards providers while sustaining the protocol

### DCA Module - Swap Fees
- Per-swap fee (up to 1%)
- Deducted from each automated swap execution
- Compensates for swap execution infrastructure

### Buy Module
- No fees

## Security Patterns

### Input Validation
- Amount validation ensures allocations match inputs within tolerance for fee-on-transfer tokens
- Fee limits prevent excessive charges across all modules

### Access Control
- Position ownership enforced via NFT holder checks
- Admin functions restricted to owner
- Designated swapper for DCA prevents unauthorized execution

### Safe Token Handling
- Balance measurements before/after transfers handle fee-on-transfer tokens
- Rounding tolerance accounts for calculation precision
- Checks-Effects-Interactions pattern followed throughout

## External Integrations

- **Uniswap V3 Core** - Liquidity pools
- **Uniswap V3 Periphery** - NFT Position Manager for LP positions
- **Uniswap Universal Router** - All token swaps

## Position Lifecycle Example

```
1. User creates Strategy position
   ├─> Deducts deposit fees (strategist/referrer/protocol)
   ├─> Creates Buy position → receives Buy NFT
   ├─> Creates DCA position → receives DCA NFT
   ├─> Creates Liquidity position → receives Liquidity NFT
   └─> Mints Strategy NFT wrapping all three

2. User collects from Strategy position
   ├─> Buy: sends purchased tokens
   ├─> DCA: sends accumulated swapped tokens (position continues)
   └─> Liquidity: collects LP fees, distributes to user/strategist/treasury

3. User closes Strategy position
   ├─> Buy: returns all tokens, burns Buy NFT
   ├─> DCA: returns remaining input + output tokens, burns DCA NFT
   ├─> Liquidity: removes liquidity, collects fees, burns Liquidity NFT
   └─> Burns Strategy NFT
```
