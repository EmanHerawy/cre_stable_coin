# Network Deployment Guide

## Overview

The StableCoin system now supports **automatic USDT detection and deployment** across 15+ networks. The deployment script automatically:

1. ✅ Detects the current network
2. ✅ Finds the correct USDT address for that network
3. ✅ Deploys MockUSDT if USDT isn't available
4. ✅ Deploys the StableCoin system with the correct configuration

## Supported Networks

### Mainnets with Real USDT

| Network | Chain ID | USDT Address |
|---------|----------|--------------|
| Ethereum | 1 | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |
| Polygon | 137 | `0xc2132D05D31c914a87C6611C10748AEb04B58e8F` |
| Arbitrum One | 42161 | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |
| Optimism | 10 | `0x94b008aA00579c1307B0EF2c499aD98a8ce58e58` |
| Base | 8453 | `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2` |
| Avalanche C-Chain | 43114 | `0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7` |
| BNB Smart Chain | 56 | `0x55d398326f99059fF775485246999027B3197955` |

### Testnets with Real USDT

| Network | Chain ID | USDT Address |
|---------|----------|--------------|
| Sepolia | 11155111 | `0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0` |
| Goerli (deprecated) | 5 | `0x509Ee0d083DdF8AC028f2a56731412edD63223B9` |
| Polygon Mumbai | 80001 | `0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832` |
| BSC Testnet | 97 | `0x337610d27c682E347C9cD60BD4b3b107C9d34dDd` |

### Networks Without USDT

For any network where USDT isn't deployed, the system automatically deploys **MockUSDT** with:
- ✅ Standard ERC20 interface
- ✅ 6 decimals (matching real USDT)
- ✅ 1 billion initial supply
- ✅ Mint/burn functions for testing

This includes:
- Arbitrum Sepolia (421614)
- Optimism Sepolia (11155420)
- Base Sepolia (84532)
- Avalanche Fuji (43113)
- Local networks (31337)
- Custom networks

## Quick Start Deployment

### 1. Set Environment Variables

Create `.env` file:

```bash
# Required
PRIVATE_KEY=0x...                    # Deployer private key
ADMIN_ADDRESS=0x...                  # Admin address for governance

# Currency Configuration
CURRENCY_NAME="Palestinian Shekel Digital"
CURRENCY_SYMBOL="PLSd"
INITIAL_RATE=3223000                 # 3.223 ILS per USDT (6 decimals)

# Optional - Chainlink CRE Configuration
FORWARDER_ADDRESS=0x...              # Keystone forwarder address
AUTHOR_ADDRESS=0x...                 # Expected workflow author
WORKFLOW_ID=0x...                    # Expected workflow ID
WORKFLOW_NAME=USDT_ILS               # Workflow name (max 10 chars)

# Optional - Override USDT address (not recommended)
# USDT_ADDRESS=0x...                 # Leave unset for auto-detection
```

### 2. Deploy to Any Network

```bash
# Ethereum Mainnet
forge script script/Deploy.s.sol --rpc-url https://eth.llamarpc.com --broadcast --verify

# Polygon
forge script script/Deploy.s.sol --rpc-url https://polygon.llamarpc.com --broadcast --verify

# Arbitrum
forge script script/Deploy.s.sol --rpc-url https://arb1.arbitrum.io/rpc --broadcast --verify

# BSC
forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.binance.org --broadcast --verify

# Sepolia Testnet
forge script script/Deploy.s.sol --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY --broadcast --verify

# Local Network (Anvil) - will deploy MockUSDT
anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Deployment Flow

### With Real USDT

```
1. Load configuration from environment
   ↓
2. Detect network (Chain ID)
   ↓
3. USDTAddressProvider.getUSDTAddress()
   ↓
4. Found USDT at 0xdAC17F958D2ee523a2206206994597C13D831ec7
   ↓
5. Deploy PriceFeedReceiver
   ↓
6. Deploy LocalCurrencyToken (with real USDT)
   ✓ Complete
```

### Without USDT (Auto-Deploy Mock)

```
1. Load configuration from environment
   ↓
2. Detect network (Chain ID: 421614 - Arbitrum Sepolia)
   ↓
3. USDTAddressProvider.getUSDTAddress()
   ↓
4. USDT not found on this network
   ↓
5. Deploy MockUSDT
   ↓
6. MockUSDT deployed at 0x123...
   ↓
7. Deploy PriceFeedReceiver
   ↓
8. Deploy LocalCurrencyToken (with MockUSDT)
   ✓ Complete
```

## Example Deployment Output

### Ethereum Mainnet (Real USDT)

```
=== StableCoin Deployment ===
Network: Ethereum Mainnet
Chain ID: 1
Admin Address: 0xYourAdminAddress
Initial Rate: 3223000
Currency: Palestinian Shekel Digital

Using existing USDT at: 0xdAC17F958D2ee523a2206206994597C13D831ec7

Deploying PriceFeedReceiver...
PriceFeedReceiver deployed at: 0x1234...

Deploying LocalCurrencyToken...
LocalCurrencyToken deployed at: 0x5678...

=== Deployment Summary ===
PriceFeedReceiver: 0x1234...
LocalCurrencyToken: 0x5678...
Token Name: Palestinian Shekel Digital
Token Symbol: PLSd
Initial Rate: 3223000
Using Oracle: false
Min Deposit: 1000000
Min Withdrawal: 1000000
Max Price Age: 3600

Deployment complete!
```

### Local Network (MockUSDT)

```
=== StableCoin Deployment ===
Network: Unknown Network
Chain ID: 31337
Admin Address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Initial Rate: 50000000
Currency: Egyptian Pound Digital

USDT not found on this network, deploying MockUSDT...
MockUSDT deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512

Deploying PriceFeedReceiver...
PriceFeedReceiver deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3

Deploying LocalCurrencyToken...
LocalCurrencyToken deployed at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

=== Deployment Summary ===
...
Deployment complete!
```

## Network-Specific Deployment

### Ethereum Mainnet

```bash
# .env
PRIVATE_KEY=0x...
ADMIN_ADDRESS=0x...
CURRENCY_NAME="Palestinian Shekel Digital"
CURRENCY_SYMBOL="PLSd"
INITIAL_RATE=3223000

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url https://eth.llamarpc.com \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Polygon

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://polygon.llamarpc.com \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY
```

### Arbitrum

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://arb1.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

### BSC

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://bsc-dataseed.binance.org \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY
```

## Testing Before Deployment

### 1. Run Unit Tests

```bash
forge test
```

### 2. Run Fork Tests on Target Network

```bash
# Test on Ethereum before deploying to Ethereum
forge test --match-contract ForkTest --fork-url https://eth.llamarpc.com -vv

# Test on Polygon before deploying to Polygon
forge test --match-contract ForkTest --fork-url https://polygon.llamarpc.com -vv
```

### 3. Simulate Deployment

```bash
# Dry run without broadcasting
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# With detailed output
forge script script/Deploy.s.sol --rpc-url $RPC_URL -vvvv
```

## Multi-Network Deployment

Deploy to multiple networks with a single script:

```bash
#!/bin/bash
# deploy-all.sh

networks=(
    "Ethereum:https://eth.llamarpc.com:$ETHERSCAN_API_KEY"
    "Polygon:https://polygon.llamarpc.com:$POLYGONSCAN_API_KEY"
    "Arbitrum:https://arb1.arbitrum.io/rpc:$ARBISCAN_API_KEY"
    "BSC:https://bsc-dataseed.binance.org:$BSCSCAN_API_KEY"
)

for network in "${networks[@]}" ; do
    IFS=: read -r name rpc api_key <<< "$network"

    echo "================================"
    echo "Deploying to $name"
    echo "================================"

    forge script script/Deploy.s.sol \
        --rpc-url "$rpc" \
        --broadcast \
        --verify \
        --etherscan-api-key "$api_key"

    echo ""
    sleep 5
done
```

## Post-Deployment Verification

### 1. Verify Contract Source

```bash
# Etherscan
forge verify-contract \
    --chain mainnet \
    --constructor-args $(cast abi-encode "constructor(address,string,string,uint256,address,address)" ...) \
    CONTRACT_ADDRESS \
    src/StableCoin.sol:LocalCurrencyToken \
    YOUR_ETHERSCAN_API_KEY
```

### 2. Check Deployment

```bash
# Use the verify function
forge script script/Deploy.s.sol --sig "verify(address,address)" \
    PRICE_FEED_RECEIVER_ADDRESS \
    STABLECOIN_ADDRESS \
    --rpc-url $RPC_URL
```

### 3. Manual Verification

```bash
# Check token info
cast call STABLECOIN_ADDRESS "name()(string)" --rpc-url $RPC_URL
cast call STABLECOIN_ADDRESS "symbol()(string)" --rpc-url $RPC_URL
cast call STABLECOIN_ADDRESS "usdt()(address)" --rpc-url $RPC_URL

# Check admin
cast call STABLECOIN_ADDRESS "hasRole(bytes32,address)(bool)" \
    $(cast keccak "ADMIN_ROLE()") \
    ADMIN_ADDRESS \
    --rpc-url $RPC_URL
```

## Configuration Examples

### Different Currencies

```bash
# Egyptian Pound
CURRENCY_NAME="Egyptian Pound Digital"
CURRENCY_SYMBOL="EGPd"
INITIAL_RATE=50000000  # 50 EGP per USDT

# Turkish Lira
CURRENCY_NAME="Turkish Lira Digital"
CURRENCY_SYMBOL="TRYd"
INITIAL_RATE=32500000  # 32.5 TRY per USDT

# Palestinian Shekel
CURRENCY_NAME="Palestinian Shekel Digital"
CURRENCY_SYMBOL="PLSd"
INITIAL_RATE=3223000   # 3.223 ILS per USDT
```

## Troubleshooting

### USDT Address Not Found

If deployment can't find USDT on a known network:

1. Check you're on the right network: `cast chain-id --rpc-url $RPC_URL`
2. Verify network is supported in `USDTAddressProvider.sol`
3. Manually set USDT address: `USDT_ADDRESS=0x... forge script ...`

### MockUSDT Deployed on Mainnet

If MockUSDT is being deployed on a mainnet:

1. **Stop immediately** - this shouldn't happen on mainnets
2. Check the USDT address in `USDTAddressProvider.sol` for that chain
3. Update the provider if the address is wrong

### Verification Failed

```bash
# Get constructor args
cast abi-encode "constructor(address,string,string,uint256,address,address)" \
    USDT_ADDRESS \
    "Palestinian Shekel Digital" \
    "PLSd" \
    3223000 \
    ADMIN_ADDRESS \
    PRICE_FEED_ADDRESS > constructor-args.txt

# Verify with file
forge verify-contract \
    --constructor-args-path constructor-args.txt \
    --chain-id CHAIN_ID \
    CONTRACT_ADDRESS \
    src/StableCoin.sol:LocalCurrencyToken \
    ETHERSCAN_API_KEY
```

## Security Checklist

Before mainnet deployment:

- [ ] Run all unit tests: `forge test`
- [ ] Run fork tests on target network
- [ ] Run invariant tests: `forge test --match-contract InvariantTest`
- [ ] Audit admin address (has it been securely generated?)
- [ ] Verify USDT address is correct for network
- [ ] Test deployment on testnet first
- [ ] Get security audit
- [ ] Set up monitoring and alerts
- [ ] Have pause mechanism ready (admin can pause)
- [ ] Document recovery procedures

## Cost Estimates

Approximate gas costs for deployment:

| Network | MockUSDT | PriceFeedReceiver | LocalCurrencyToken | Total |
|---------|----------|-------------------|-------------------|-------|
| Ethereum | 1.2M | 800k | 3.5M | ~5.5M gas |
| Polygon | 1.2M | 800k | 3.5M | ~5.5M gas |
| Arbitrum | 1.2M | 800k | 3.5M | ~5.5M gas |
| BSC | 1.2M | 800k | 3.5M | ~5.5M gas |

At current gas prices:
- **Ethereum**: ~$100-500 depending on gas price
- **Polygon**: ~$0.10-1
- **Arbitrum**: ~$5-20
- **BSC**: ~$1-5

## Next Steps After Deployment

1. **Configure Oracle** (if using Chainlink CRE):
   ```bash
   cast send STABLECOIN_ADDRESS \
       "setUseOracle(bool)" true \
       --private-key $PRIVATE_KEY \
       --rpc-url $RPC_URL
   ```

2. **Set Fees** (if desired):
   ```bash
   # 0.5% mint fee
   cast send STABLECOIN_ADDRESS \
       "setMintFee(uint256)" 50 \
       --private-key $PRIVATE_KEY \
       --rpc-url $RPC_URL
   ```

3. **Transfer Admin** (if needed):
   ```bash
   cast send STABLECOIN_ADDRESS \
       "grantRole(bytes32,address)" \
       $(cast keccak "ADMIN_ROLE()") \
       NEW_ADMIN_ADDRESS \
       --private-key $PRIVATE_KEY \
       --rpc-url $RPC_URL
   ```

4. **Monitor Deployment**:
   - Set up block explorer alerts
   - Monitor for first mint/redeem transactions
   - Track collateral ratio
   - Watch for oracle updates (if enabled)
