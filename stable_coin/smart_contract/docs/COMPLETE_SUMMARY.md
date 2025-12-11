# Complete StableCoin System Summary

## System Overview

A complete USDT-backed stablecoin system with automatic price feed updates via Chainlink CRE.

### Components

1. **Smart Contracts** (Solidity)
   - `PriceFeedReceiver.sol` - Receives price updates from Chainlink CRE
   - `StableCoin.sol` (LocalCurrencyToken) - ERC20 stablecoin backed by USDT

2. **Chainlink CRE Workflow** (TypeScript)
   - `main.ts` - Fetches USDT/ILS prices and updates on-chain contract

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ External Data Sources                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CoinGecko API           ExchangeRate-API                      │
│  └─ USDT/USD rate        └─ USD/ILS rate                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Chainlink CRE Workflow (Off-chain)                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  main.ts                                                        │
│  ├─ Fetches USDT/USD and USD/ILS rates                         │
│  ├─ Calculates USDT/ILS rate                                   │
│  ├─ Converts to 8 decimals                                     │
│  └─ Submits to PriceFeedReceiver                               │
│                                                                 │
│  Schedule: Every 10-15 minutes (production - configurable)                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Smart Contracts (On-chain)                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PriceFeedReceiver.sol                                          │
│  ├─ Validates sender (Keystone Forwarder)                      │
│  ├─ Validates workflow ID, author, name                        │
│  ├─ Stores: latestPrice (uint224, 8 decimals)                  │
│  └─ Stores: latestTimestamp (uint32)                           │
│                                                                 │
│                    ↓                                            │
│                                                                 │
│  StableCoin.sol (LocalCurrencyToken)                            │
│  ├─ Queries PriceFeedReceiver for price                        │
│  ├─ Converts 8 decimals → 6 decimals                           │
│  ├─ Mint: USDT → ILS tokens                                    │
│  ├─ Redeem: ILS tokens → USDT                                  │
│  └─ Fallback to manual rate if oracle stale                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Users                                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ├─ Deposit USDT, receive ILS tokens                           │
│  ├─ Redeem ILS tokens, receive USDT                            │
│  └─ Rate updates automatically every 1 minute                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files Overview

### Smart Contracts (`/smart_contract/`)

| File | Purpose | Lines |
|------|---------|-------|
| `src/PriceFeedReceiver.sol` | Receives & stores price updates from Chainlink CRE | 215 |
| `src/StableCoin.sol` | USDT-backed ERC20 stablecoin | 423 |
| `test/PriceFeedReceiver.t.sol` | Unit tests for PriceFeedReceiver | 176 |
| `test/StableCoin.t.sol` | Unit tests for StableCoin | 542 |
| `script/Deploy.s.sol` | Production deployment script | 184 |
| `script/DeployTest.s.sol` | Test deployment with mock USDT | 146 |

### Chainlink CRE Workflow (`/stable_coin/`)

| File | Purpose | Lines |
|------|---------|-------|
| `main.ts` | Price feed workflow | 317 |
| `temp.ts` | Reference implementation (rate calculation) | 176 |
| `config.example.yaml` | Configuration template | 15 |



## Test Results

### Smart Contracts

✅ **All 104 tests passing**

#### PriceFeedReceiver (15 tests)
- Initial state verification
- Configuration management (forwarders, workflow IDs, authors, workflow names)
- Duplicate prevention
- Price report processing
- Authorization checks
- Access control

#### StableCoin (40 tests)
- Constructor validation
- Mint functionality (manual & oracle rates)
- Redeem functionality
- Rate management
- Oracle integration (price fetching, stale data fallback, zero price handling)
- Pause/unpause mechanics
- Admin functions with access control
- Preview functions
- Collateral tracking
- Edge cases

#### FeeManagement (16 tests)
- Fee configuration and updates
- Mint with fees
- Redeem with fees
- Fee withdrawal
- Access control

#### Fuzz Tests (11 tests)
- Random input testing (2,827 runs)
- Edge case discovery
- Decimal precision validation

#### Invariant Tests (11 tests)
- Stateful testing (128,000 operations)
- Collateral invariants
- Fee accounting

#### Fork Tests (11 tests)
- Real USDT integration
- Multi-network testing
-  account testing

---

## Deployment Summary

### Prerequisites

1. **Smart Contracts**
   - Foundry installed
   - Private key with ETH for gas
   - USDT contract address
   - Admin address

2. **Chainlink CRE Workflow**
   - Node.js 18+
   - Chainlink CRE SDK
   - ExchangeRate-API key
   - Deployed PriceFeedReceiver address

### Smart Contract Deployment

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your values

# 2. Run tests
forge test

# 3. Dry run
forge script script/Deploy.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL -vvvv

# 4. Deploy to testnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# 5. Deploy to mainnet (after testing!)
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```


## Security Features

### Smart Contracts

1. **Access Control**
   - Role-based permissions (Admin, Pauser, Rate Updater)
   - OpenZeppelin AccessControl

2. **Pause Protection**
   - Critical parameter updates require pause
   - Prevents mid-transaction rate changes

3. **Price Validation**
   - Stale price detection (`maxPriceAge`)
   - Automatic fallback to manual rate
   - Zero price rejection

4. **Reentrancy Protection**
   - OpenZeppelin ReentrancyGuard on mint/redeem

5. **Collateral Security**
   - Direct balance queries (no tracked state)
   - SafeERC20 for transfers

### Chainlink CRE Workflow

1. **Consensus Mechanism**
   - Multiple nodes aggregate price data
   - Median calculation for numeric values

2. **Multi-Source Validation**
   - USDT/USD from CoinGecko
   - USD/ILS from ExchangeRate-API
   - Cross-validation possible

3. **Authorization**
   - Workflow ID validation
   - Author validation
   - Workflow name validation

---

## Operational Procedures

### Updating Manual Rate

```bash
# 1. Pause
cast send $STABLE_COIN_ADDRESS "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 2. Update rate (e.g., 3.65 ILS per USDT with 6 decimals)
cast send $STABLE_COIN_ADDRESS "updateManualRate(uint256)" 3650000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 3. Unpause
cast send $STABLE_COIN_ADDRESS "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Switching Between Oracle and Manual

```bash
# Pause → Toggle → Unpause
cast send $STABLE_COIN_ADDRESS "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $STABLE_COIN_ADDRESS "toggleUseOracle()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $STABLE_COIN_ADDRESS "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```


---

## Key Design Decisions

### 1. Single Feed Architecture
- One PriceFeedReceiver per currency pair
- Simpler, cheaper, safer than multi-feed

### 2. Pause Protection
- Critical functions require pause
- Prevents front-running parameter changes

### 3. Oracle Fallback
- Automatic fallback to manual rate
- Stale data detection
- Try/catch for oracle failures

## License

MIT


