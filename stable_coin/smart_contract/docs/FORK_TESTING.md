# Fork Testing Documentation

## Overview

Fork tests allow you to test the StableCoin system against **real USDT contracts** deployed on various networks. This provides the highest fidelity testing by using actual mainnet/testnet state.

## What Fork Testing Tests

✅ **Real USDT Integration**: Tests against actual USDT contracts, not mocks
✅ **Network Compatibility**: Verifies system works on all supported networks
✅ **Real Transfer Behavior**: Tests actual USDT transfer/approve mechanisms
✅ **Gas Costs**: Measures real gas costs on each network
✅ **Large Amounts**: Tests with real whale accounts holding millions of USDT

## Supported Networks

The fork tests support all networks where USDT is deployed:

### Mainnets
- **Ethereum** (Chain ID: 1) - USDT: `0xdAC17F958D2ee523a2206206994597C13D831ec7`
- **Polygon** (Chain ID: 137) - USDT: `0xc2132D05D31c914a87C6611C10748AEb04B58e8F`
- **Arbitrum** (Chain ID: 42161) - USDT: `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9`
- **Optimism** (Chain ID: 10) - USDT: `0x94b008aA00579c1307B0EF2c499aD98a8ce58e58`
- **Base** (Chain ID: 8453) - USDT: `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2`
- **Avalanche** (Chain ID: 43114) - USDT: `0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7`
- **BSC** (Chain ID: 56) - USDT: `0x55d398326f99059fF775485246999027B3197955`

### Testnets
- **Sepolia** (Chain ID: 11155111)
- **Polygon Mumbai** (Chain ID: 80001)
- **BSC Testnet** (Chain ID: 97)

## Running Fork Tests

### Quick Start

```bash
# Ethereum Mainnet
forge test --match-contract ForkTest --fork-url https://eth.llamarpc.com -vv

# Polygon
forge test --match-contract ForkTest --fork-url https://polygon.llamarpc.com -vv

# Arbitrum
forge test --match-contract ForkTest --fork-url https://arb1.arbitrum.io/rpc -vv

# BSC
forge test --match-contract ForkTest --fork-url https://bsc-dataseed.binance.org -vv

# Optimism
forge test --match-contract ForkTest --fork-url https://mainnet.optimism.io -vv

# Base
forge test --match-contract ForkTest --fork-url https://mainnet.base.org -vv

# Avalanche
forge test --match-contract ForkTest --fork-url https://api.avax.network/ext/bc/C/rpc -vv
```

### Using Alchemy/Infura

```bash
# Ethereum with Alchemy
forge test --match-contract ForkTest --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY -vv

# Polygon with Alchemy
forge test --match-contract ForkTest --fork-url https://polygon-mainnet.g.alchemy.com/v2/YOUR_API_KEY -vv

# Sepolia Testnet
forge test --match-contract ForkTest --fork-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY -vv
```

### Environment Variables

Set up `.env` for easier testing:

```bash
# .env
ETH_RPC_URL=https://eth.llamarpc.com
POLYGON_RPC_URL=https://polygon.llamarpc.com
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
BSC_RPC_URL=https://bsc-dataseed.binance.org
OPTIMISM_RPC_URL=https://mainnet.optimism.io
BASE_RPC_URL=https://mainnet.base.org
AVALANCHE_RPC_URL=https://api.avax.network/ext/bc/C/rpc
```

Then use:
```bash
source .env
forge test --match-contract ForkTest --fork-url $ETH_RPC_URL -vv
```

## Test Coverage

### Basic Tests
- ✅ `testFork_USDTExists` - Verify USDT contract is valid
- ✅ `testFork_MintWithRealUSDT` - Mint tokens with real USDT
- ✅ `testFork_RedeemWithRealUSDT` - Redeem tokens for real USDT
- ✅ `testFork_MultipleUsersWithRealUSDT` - Multi-user scenarios

### Fee Tests
- ✅ `testFork_FeesWithRealUSDT` - Fee collection and withdrawal with real USDT

### Edge Cases
- ✅ `testFork_LargeAmountWithRealUSDT` - Large amounts (50k+ USDT)
- ✅ `testFork_SequentialOperations` - Many sequential operations

### Network Tests
- ✅ `testFork_CorrectNetworkDetection` - Verify network auto-detection
- ✅ `testFork_RealUSDTTransferBehavior` - Test real USDT quirks

### Performance
- ✅ `testFork_GasCosts` - Measure real gas costs on each network
- ✅ `testFork_CollateralRatioMaintained` - Verify 100% collateralization

## How Fork Tests Work

### 1. Network Detection
```solidity
address usdtAddress = USDTAddressProvider.getUSDTAddress();
```
Automatically detects and uses the correct USDT contract for the forked network.

### 2. Whale Funding
```solidity
address whale = whaleAddresses[block.chainid];
vm.startPrank(whale);
usdt.transfer(user1, 10000e6);
```
Impersonates real whale accounts (Binance, Coinbase) to fund test users with real USDT.

### 3. Real Contract Interaction
```solidity
usdt.approve(address(stableCoin), amount);
stableCoin.mint(amount);
```
All interactions use the actual USDT contract deployed on the network.

## Whale Addresses

The tests use these real accounts with large USDT balances:

| Network | Whale | Type |
|---------|-------|------|
| Ethereum | `0x28C6c06298d514Db089934071355E5743bf21d60` | Binance Hot Wallet |
| Polygon | `0x2cf7252e74036d1Da831d11089D326296e64a728` | Binance Hot Wallet |
| Arbitrum | `0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D` | Binance Hot Wallet |
| BSC | `0x8894E0a0c962CB723c1976a4421c95949bE2D4E3` | Binance Hot Wallet |
| Optimism | `0x94b008aA00579c1307B0EF2c499aD98a8ce58e58` | USDT Bridge |
| Base | `0x4c80E24119CFB836cdF0a6b53dc23F04F7e652CA` | Coinbase |
| Avalanche | `0x9f8c163cBA728e99993ABe7495F06c0A3c8Ac8b9` | Binance Hot Wallet |

## Expected Output

Successful test run should show:

```
Running fork tests on: Ethereum Mainnet
Chain ID: 1
USDT Address: 0xdAC17F958D2ee523a2206206994597C13D831ec7
StableCoin deployed at: 0x...
Whale balance: 1234567890000000
User1 funded with: 10000000000
User2 funded with: 10000000000

[PASS] testFork_USDTExists() (gas: 23451)
[PASS] testFork_MintWithRealUSDT() (gas: 187234)
[PASS] testFork_RedeemWithRealUSDT() (gas: 201567)
[PASS] testFork_MultipleUsersWithRealUSDT() (gas: 345678)
[PASS] testFork_FeesWithRealUSDT() (gas: 234567)
[PASS] testFork_CollateralRatioMaintained() (gas: 456789)

=== Gas Costs on Real Network ===
Network: Ethereum Mainnet
Mint gas: 137892
Redeem gas: 156234

Test result: ok. 14 passed; 0 failed
```

## Running Specific Tests

```bash
# Run only basic tests
forge test --match-contract ForkTest --match-test testFork_Mint --fork-url $ETH_RPC_URL -vv

# Run only fee tests
forge test --match-contract ForkTest --match-test testFork_Fees --fork-url $ETH_RPC_URL -vv

# Run with increased verbosity for debugging
forge test --match-contract ForkTest --fork-url $ETH_RPC_URL -vvvv
```

## Testing on Multiple Networks

Run fork tests on all networks:

```bash
#!/bin/bash
# test-all-networks.sh

networks=(
    "Ethereum:https://eth.llamarpc.com"
    "Polygon:https://polygon.llamarpc.com"
    "Arbitrum:https://arb1.arbitrum.io/rpc"
    "BSC:https://bsc-dataseed.binance.org"
    "Optimism:https://mainnet.optimism.io"
    "Base:https://mainnet.base.org"
    "Avalanche:https://api.avax.network/ext/bc/C/rpc"
)

for network in "${networks[@]}" ; do
    NAME="${network%%:*}"
    URL="${network##*:}"

    echo "================================"
    echo "Testing on $NAME"
    echo "================================"

    forge test --match-contract ForkTest --fork-url "$URL" -vv

    echo ""
done
```

## Troubleshooting

### Rate Limiting
If you hit rate limits with public RPCs:
- Use Alchemy/Infura with an API key
- Add delays between test runs
- Use `--fork-block-number` to cache a specific block

### Whale Balance Too Low
If whale doesn't have enough USDT:
- Update whale address to a different account
- Use a more recent fork block: `--fork-block-number latest`
- Reduce test amounts

### RPC Connection Issues
```bash
# Use a different RPC provider
forge test --match-contract ForkTest --fork-url https://rpc.ankr.com/eth -vv

# Or set a higher timeout
FOUNDRY_FORK_REQUEST_TIMEOUT=60000 forge test --match-contract ForkTest --fork-url $ETH_RPC_URL
```

## Caching Fork State

To speed up repeated test runs, cache the fork state:

```bash
# First run - will cache state
forge test --match-contract ForkTest --fork-url $ETH_RPC_URL --fork-block-number 18000000

# Subsequent runs use cached state (much faster)
forge test --match-contract ForkTest --fork-url $ETH_RPC_URL --fork-block-number 18000000
```


