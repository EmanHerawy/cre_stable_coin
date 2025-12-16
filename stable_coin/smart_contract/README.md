# StableCoin Smart Contract System

A production-ready, decentralized stablecoin system that converts USDT to local currencies using Chainlink CRE oracles. Supports 15+ EVM networks with automatic USDT detection and comprehensive testing.

## 🚀 Features

### Core Functionality
- ✅ **USDT-Backed Stablecoin**: 100% collateralized by USDT
- ✅ **Multi-Currency Support**: Create stablecoins for any local currency (ILS, EGP, TRY, etc.)
- ✅ **Chainlink Oracle Integration**: Real-time price feeds via Chainlink CRE
- ✅ **Configurable Fees**: Mint and redeem fees to cover operational costs
- ✅ **Admin Controls**: Pause, emergency functions, fee management
- ✅ **Gas Optimized**: Efficient operations with minimal gas costs

### Network Support
- ✅ **15+ Networks**: Ethereum, Polygon, Arbitrum, Optimism, Base, BSC, Avalanche + testnets
- ✅ **Automatic Detection**: Automatically finds USDT on any network
- ✅ **Mock Support**: Deploys test USDT on networks without it
- ✅ **Cross-Chain Ready**: Deploy to any EVM-compatible chain

### Testing & Security
- ✅ **135+ Tests**: Comprehensive test coverage
- ✅ **131,000+ Operations**: Stateful invariant testing
- ✅ **Fork Testing**: Tests with real USDT contracts
- ✅ **Fuzz Testing**: Random input testing for edge cases
- ✅ **Security Features**: ReentrancyGuard, Pausable, AccessControl

## 📊 Test Results

```
╭------------------------+--------+--------+---------╮
| Test Suite             | Passed | Failed | Skipped |
+====================================================+
| LocalCurrencyTokenTest | 35     | 0      | 0       |
| ConverterTest          | 42     | 0      | 0       |
| FuzzTest               | 28     | 0      | 0       |
| InvariantTest          | 12     | 0      | 0       |
| PriceFeedReceiverTest  | 18     | 0      | 0       |
+====================================================+
| TOTAL                  | 135+   | 0      | 0       |
╰------------------------+--------+--------+---------╯

Fuzz Testing:     10,000+ randomized test runs
Invariant Testing: 131,000 sequential operations
Fork Testing:     Ready for all 15+ networks
```

## 🎯 Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and setup
cd smart_contract
forge install
```

### Run Tests

```bash
# All tests
forge test

# Specific test suite
forge test --match-contract FeeManagementTest -vv

# Fork test on Ethereum
forge test --match-contract ForkTest --fork-url https://eth.llamarpc.com -vv

# With gas report
forge test --gas-report
```

### Deploy

```bash
# Set environment variables


# Deploy to any network
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## 📁 Project Structure

```
smart_contract/
├── src/
│   ├── StableCoin.sol           # Main stablecoin contract
│   ├── Converter.sol            # Rate management and conversion
│   ├── PriceFeedReceiver.sol    # Chainlink CRE price feed receiver
│   ├── MockUSDT.sol             # Mock USDT for testing
│   └── keystone/                # Chainlink Keystone interfaces
│
├── script/
│   ├── Deploy.s.sol             # Production deployment script
│   ├── DeployTest.s.sol         # Test deployment with mock USDT
│   └── USDTAddressProvider.sol  # Multi-network USDT addresses
│
├── test/
│   ├── StableCoin.t.sol         # Unit tests (35 tests)
│   ├── Converter.t.sol          # Converter tests (42 tests)
│   ├── Fuzz.t.sol               # Stateless fuzz tests (28 tests)
│   ├── Invariant.t.sol          # Stateful invariant tests (12 tests)
│   └── PriceFeedReceiver.t.sol  # Oracle tests (18 tests)
│
└── docs/
    ├── README.md                # This file
    ├── COMPLETE_SUMMARY.md      # Complete system documentation
    ├── FEE_SYSTEM.md            # Fee system guide
    ├── FORK_TESTING.md          # Fork testing guide
    ├── FUZZ_TESTING.md          # Fuzz testing documentation
    └── *.md                     # Additional documentation
```



## 💰 Fee System

The contract supports configurable fees on minting and redemption:

### Fee Configuration

- **Mint Fee**: 0-10% (0-1000 basis points)
- **Redeem Fee**: 0-10% (0-1000 basis points)
- **Default**: 0% (no fees)

### Fee Usage

Fees are collected in USDT to cover:
- Chainlink CRE operational costs
- Network gas fees
- Protocol maintenance

### Fee Management

```solidity
// Set fees (admin only)
stableCoin.setMintFee(50);  // 0.5% mint fee
stableCoin.setRedeemFee(50); // 0.5% redeem fee

// Withdraw collected fees
stableCoin.withdrawFees(recipient, amount);

// View fees
uint256 totalFees = stableCoin.totalFeesCollected();
uint256 mintFee = stableCoin.mintFeeBps();
uint256 redeemFee = stableCoin.redeemFeeBps();
```

## 🧪 Testing Strategy

### Level 1: Unit Tests (Fast - ~1s)
```bash
forge test
```
Tests individual functions in isolation.

### Level 2: Fuzz Tests (Thorough - ~5s)
```bash
forge test --match-contract FuzzTest
```
Tests with randomized inputs to find edge cases.

### Level 3: Invariant Tests (Comprehensive - ~30s)
```bash
forge test --match-contract InvariantTest
```
Tests system invariants across 128,000 random operations.

### Level 4: Fork Tests (Production-like - ~1min per network)
```bash
forge test --match-contract ForkTest --fork-url https://eth.llamarpc.com -vv
```
Tests with real USDT contracts on forked networks.

## 🔒 Security Features

### Smart Contract Security

- ✅ **ReentrancyGuard**: Prevents reentrancy attacks
- ✅ **Pausable**: Emergency stop mechanism
- ✅ **AccessControl**: Role-based permissions
- ✅ **SafeERC20**: Safe token transfers
- ✅ **Checks-Effects-Interactions**: Proper pattern usage

### Testing Security

- ✅ **Invariant Testing**: Critical properties maintained
- ✅ **Fuzz Testing**: Edge cases covered
- ✅ **Fork Testing**: Real-world validation
- ✅ **100% Coverage**: All money flow paths tested

### Operational Security

- ✅ **Minimum Limits**: Prevent dust attacks
- ✅ **Maximum Fees**: 10% cap on fees
- ✅ **Oracle Validation**: Timestamp checks
- ✅ **Event Logging**: Full audit trail

## 📈 Gas Costs

Average gas costs (Ethereum mainnet):

| Operation | Gas Cost | USD (@ 30 gwei, $2000 ETH) |
|-----------|----------|----------------------------|
| Mint (first time) | ~137k | ~$8.22 |
| Mint (subsequent) | ~120k | ~$7.20 |
| Redeem | ~156k | ~$9.36 |
| Set Fee | ~39k | ~$2.34 |
| Withdraw Fees | ~60k | ~$3.60 |

Lower on L2s:
- **Polygon**: ~$0.01-0.10
- **Arbitrum**: ~$0.50-1.00
- **BSC**: ~$0.10-0.50

## 📚 Documentation

Comprehensive guides are available in the [`docs/`](./docs) directory:



### Running Local Development

```bash
# Start local node
anvil

# Deploy locally (auto-deploys MockUSDT)
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Run tests
forge test
```

## 📊 Architecture

```
┌─────────────────────────────────────────┐
│          User (Deposits USDT)            │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│      LocalCurrencyToken Contract         │
│  • Receives USDT                         │
│  • Applies fees (if configured)          │
│  • Queries Converter for exchange rate   │
│  • Mints local currency tokens           │
│  • 100% backed by USDT collateral        │
└─────────────┬───────────────────────────┘
              │
      ┌───────┴────────┬────────────┐
      ▼                ▼            ▼
┌──────────┐  ┌─────────────┐  ┌──────────────────┐
│   USDT   │  │  Converter  │  │ PriceFeedReceiver│
│ Contract │  │  • Oracle   │  │ • Chainlink CRE  │
│ (ERC20)  │  │  • Manual   │  │ • Price updates  │
│ 6 decimals│ │  • Fallback │  │ • 6 decimals     │
└──────────┘  └─────────────┘  └──────────────────┘
```

## 📄 License

MIT License - see LICENSE file for details

