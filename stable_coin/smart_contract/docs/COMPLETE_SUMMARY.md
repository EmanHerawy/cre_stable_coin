# Complete StableCoin System Summary

## System Overview

A complete USDT-backed stablecoin system with automatic price feed updates via Chainlink CRE.

### Components

1. **Smart Contracts** (Solidity)
   - `PriceFeedReceiver.sol` - Receives price updates from Chainlink CRE
   - `Converter.sol` - Rate management with oracle/manual fallback
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
│  ├─ Converts to 6 decimals                                     │
│  └─ Submits to PriceFeedReceiver                               │
│                                                                 │
│  Schedule: Every 10-15 minutes (production - configurable)      │
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
│  Converter.sol                                                  │
│  ├─ Queries PriceFeedReceiver for oracle price (if configured) │
│  ├─ Manages manual rate (admin controlled)                     │
│  ├─ Automatic fallback if oracle stale or invalid              │
│  ├─ Deviation checks and validation                            │
│  └─ Provides conversion: USDT ↔ Local Currency                 │
│                                                                 │
│                    ↓                                            │
│                                                                 │
│  StableCoin.sol (LocalCurrencyToken)                            │
│  ├─ Queries Converter for exchange rate                        │
│  ├─ Mint: USDT → local-currency tokens                         │
│  ├─ Redeem: local-currency tokens → USDT                       │
│  └─ Fee collection and management                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Users                                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ├─ Deposit USDT, receive ILS tokens                           │
│  ├─ Redeem ILS tokens, receive USDT                            │
│  └─ Rate updates automatically every 10-15 minutes             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files Overview

### Smart Contracts (`/smart_contract/`)

| File | Purpose | Lines |
|------|---------|-------|
| `src/PriceFeedReceiver.sol` | Receives & stores price updates from Chainlink CRE | 320 |
| `src/Converter.sol` | Rate management with oracle/manual fallback | 500+ |
| `src/StableCoin.sol` | USDT-backed ERC20 stablecoin | 450+ |
| `test/PriceFeedReceiver.t.sol` | Unit tests for PriceFeedReceiver | 180+ |
| `test/Converter.t.sol` | Unit tests for Converter (42 tests) | 1200+ |
| `test/StableCoin.t.sol` | Unit tests for StableCoin (30+ tests) | 900+ |
| `test/Fuzz.t.sol` | Stateless fuzz tests (28 tests) | 700+ |
| `test/Invariant.t.sol` | Stateful invariant tests (12 tests) | 400+ |
| `script/Deploy.s.sol` | Production deployment script | 200+ |
| `script/DeployTest.s.sol` | Test deployment with mock USDT | 130 |

### Chainlink CRE Workflow (`/stable_coin/`)

| File | Purpose | Lines |
|------|---------|-------|
| `main.ts` | Price feed workflow | 317 |
| `temp.ts` | Reference implementation (rate calculation) | 176 |
| `config.example.yaml` | Configuration template | 15 |

---

## Test Results

### Smart Contracts

✅ **All 135+ tests passing**

#### PriceFeedReceiver (18 tests)
- Initial state verification
- Configuration management (forwarders, workflow IDs, authors, workflow names)
- Duplicate prevention
- Price report processing
- Authorization checks
- Access control
- Remove functionality for security parameters

#### Converter (42 tests)
- Manual rate management
- Oracle integration
- Fallback mechanisms
- Deviation checks and validation
- Price age verification
- Oracle/manual mode switching
- Admin controls
- Edge cases and error handling

#### StableCoin (30+ tests)
- Constructor validation
- Mint functionality with Converter integration
- Redeem functionality
- Fee management (mint & redeem fees)
- Oracle integration through Converter
- Pause/unpause mechanics
- Admin functions with access control
- Collateral tracking
- Edge cases

#### Fuzz Tests (28 tests)
- Random input testing (10,000+ runs)
- Edge case discovery
- Decimal precision validation
- Converter integration testing
- Round-trip invariants

#### Invariant Tests (12 tests)
- Stateful testing (131,000 operations)
- Collateral invariants
- Fee accounting
- Solvency checks
- Converter rate stability

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
# Update manual rate in Converter (e.g., 50 EGP per USDT with 6 decimals)
cast send $CONVERTER_ADDRESS "setManualRate(uint256)" 50000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Switching Between Oracle and Manual

```bash
# Toggle oracle mode in Converter
cast send $CONVERTER_ADDRESS "toggleUseOracle()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Updating Oracle Configuration

```bash
# Update max price age (e.g., 1 hour = 3600 seconds)
cast send $CONVERTER_ADDRESS "setMaxPriceAge(uint256)" 3600 --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Update max deviation (e.g., 20% = 2000 bps)
cast send $CONVERTER_ADDRESS "setMaxPriceDeviationBps(uint256)" 2000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```


---

## Key Design Decisions

### 1. Three-Contract Architecture
- **PriceFeedReceiver**: Receives oracle data from Chainlink CRE
- **Converter**: Rate management with oracle/manual fallback
- **StableCoin**: Token minting, redemption, and fee management
- Separation of concerns for better security and upgradability

### 2. Single Feed Architecture
- One PriceFeedReceiver per currency pair
- Simpler, cheaper, safer than multi-feed

### 3. Oracle Fallback in Converter
- Automatic fallback to manual rate when oracle is stale
- Deviation checks when oracle is active
- Manual rate always available (no deviation check in fallback)
- Configurable max price age and max deviation

### 4. Security Hardening
- Removed DoS vulnerability in fallback path
- Custom errors throughout (gas-efficient)
- Comprehensive validation and access control
- Reentrancy protection on all critical functions

## License

MIT


