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
│  Schedule: Every 1 minute (configurable)                       │
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

### Documentation

| File | Purpose |
|------|---------|
| `DEPLOYMENT.md` | Smart contract deployment guide |
| `USDT_ILS_WORKFLOW.md` | Chainlink CRE workflow guide |
| `SINGLE_FEED_ARCHITECTURE.md` | Single-feed design rationale |
| `PAUSE_PROTECTION.md` | Security strategy for parameter updates |
| `COMPLETE_SUMMARY.md` | This file |

---

## Test Results

### Smart Contracts

✅ **All 55 tests passing**

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

### Chainlink CRE Workflow Deployment

```bash
# 1. Install dependencies
cd stable_coin && bun install

# 2. Configure
# Create config.json with your values

# 3. Simulate locally
cre workflow simulate ./

# 4. Deploy to CRE
# Follow Chainlink CRE deployment docs
```

---

## Gas Costs

### Smart Contract Deployment

| Operation | Gas Used | Cost @ 3 gwei |
|-----------|----------|---------------|
| Deploy PriceFeedReceiver | 1,400,000 | ~0.004 ETH |
| Deploy LocalCurrencyToken | 3,100,000 | ~0.009 ETH |
| Configure PriceFeedReceiver | 300,000 | ~0.001 ETH |
| **Total Deployment** | **4,800,000** | **~0.014 ETH** |

### Transaction Costs

| Operation | Gas Used | Cost @ 20 gwei |
|-----------|----------|----------------|
| Mint | ~127,000 | ~0.0025 ETH |
| Redeem | ~66,000 | ~0.0013 ETH |
| Update Manual Rate | ~55,000 | ~0.0011 ETH |
| Price Update (CRE) | ~60,000 | ~0.0012 ETH |

### Monthly Operational Costs

| Update Frequency | Updates/Month | Gas Cost @ 20 gwei |
|-----------------|---------------|-------------------|
| Every 1 minute | 43,200 | ~52 ETH (~$100,000) |
| Every 5 minutes | 8,640 | ~10 ETH (~$20,000) |
| Every 30 minutes | 1,440 | ~1.7 ETH (~$3,400) |
| Every 1 hour | 720 | ~0.9 ETH (~$1,700) |

**⚠️ Recommendation**: Use 30-minute or hourly updates for stable assets to minimize costs.

---

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

## API Rate Limits & Costs

### CoinGecko (Free)
- **Rate**: 10-30 calls/minute
- **Cost**: $0
- **Key**: Not required

### ExchangeRate-API

| Plan | Requests/Month | Cost/Month |
|------|---------------|------------|
| Free | 1,500 | $0 |
| Basic | 100,000 | $10 |
| Pro | 1,500,000 | $60 |

**⚠️ Warning**: 1-minute updates need 43,200 requests/month (Pro plan required).

---

## Production Checklist

### Before Mainnet Deployment

- [ ] All tests passing (55/55)
- [ ] Deployed to Sepolia testnet
- [ ] Tested mint/redeem flows
- [ ] Verified price updates from CRE
- [ ] Tested pause/unpause
- [ ] Tested rate fallback
- [ ] Tested stale price detection
- [ ] Gas costs reviewed
- [ ] Update frequency finalized
- [ ] API rate limits configured
- [ ] Admin using multisig wallet
- [ ] Monitoring/alerts set up
- [ ] Operational procedures documented
- [ ] Emergency contacts established
- [ ] Audited (recommended for production)

---

## Key Design Decisions

### 1. Single Feed Architecture
- One PriceFeedReceiver per currency pair
- Simpler, cheaper, safer than multi-feed
- See: `SINGLE_FEED_ARCHITECTURE.md`

### 2. Direct Balance Queries
- No `totalCollateral` state variable
- Uses `usdt.balanceOf(address(this))`
- Prevents accounting issues from direct transfers

### 3. Pause Protection
- Critical functions require pause
- Prevents front-running parameter changes
- See: `PAUSE_PROTECTION.md`

### 4. Oracle Fallback
- Automatic fallback to manual rate
- Stale data detection
- Try/catch for oracle failures

### 5. Toggle Pattern
- `toggleUseOracle()` instead of `setUseOracle(bool)`
- Simpler, less error-prone

---

## Support & Troubleshooting

### Common Issues

1. **"Insufficient funds for gas"**
   - Ensure deployer/workflow wallet has ETH

2. **"Invalid address"**
   - Use checksummed addresses
   - Use `cast --to-checksum-address <addr>`

3. **"Failed to write price report"**
   - Verify PriceFeedReceiver configuration
   - Check forwarder/workflow ID/author

4. **Tests failing**
   - Run `forge clean && forge build`
   - Check Solidity version (0.8.20+)

### Resources

- **Chainlink CRE Docs**: https://docs.chain.link/cre
- **Foundry Book**: https://book.getfoundry.sh
- **OpenZeppelin Docs**: https://docs.openzeppelin.com

---

## License

MIT

---

## Contributors

- Smart Contracts: Solidity 0.8.20+
- Tests: Foundry
- Workflow: Chainlink CRE SDK
- Documentation: Complete system overview
