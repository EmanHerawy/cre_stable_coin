# Complete Deployment Guide

## Quick Start

### 1. Local Deployment (Testing)

```bash
# Terminal 1: Start local node
anvil

# Terminal 2: Deploy to local network
cd smart_contract
forge script script/DeployTest.s.sol --rpc-url http://localhost:8545 --broadcast -vvv
```

### 2. Testnet Deployment

```bash
# Set up environment
export PRIVATE_KEY=0x...
export ADMIN_ADDRESS=0x...

# Deploy to Sepolia
forge script script/Deploy.s.sol \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

### 3. Mainnet Deployment

```bash
# Deploy to Ethereum Mainnet
forge script script/Deploy.s.sol \
  --rpc-url https://eth.llamarpc.com \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

---

## Detailed Deployment Instructions

## Prerequisites

### 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Clone and Setup

```bash
cd smart_contract
forge install
forge build
```

### 3. Run Tests

```bash
# Run all tests
forge test

# Verify all tests pass
forge test --summary
```

Expected output:
```
╭------------------------+--------+--------+---------╮
| Test Suite             | Passed | Failed | Skipped |
+====================================================+
| LocalCurrencyTokenTest | 40     | 0      | 0       |
| FeeManagementTest      | 16     | 0      | 0       |
| FuzzTest               | 11     | 0      | 0       |
| InvariantTest          | 11     | 0      | 0       |
| ForkTest               | 11     | 0      | 0       |
| PriceFeedReceiverTest  | 15     | 0      | 0       |
╰------------------------+--------+--------+---------╯
```

---

## Environment Setup

### Create .env File

```bash
# Create .env file in smart_contract directory
cd smart_contract
touch .env
```

### Configure .env

```bash
# Required Configuration
PRIVATE_KEY=0x...                    # Your deployer private key (NEVER commit this!)
ADMIN_ADDRESS=0x...                  # Admin address for governance

# Currency Configuration
CURRENCY_NAME="Palestinian Shekel Digital"
CURRENCY_SYMBOL="PLSd"
INITIAL_RATE=3223000                 # 3.223 ILS per USDT (6 decimals)

# Optional - Chainlink CRE Configuration (if using oracle)
FORWARDER_ADDRESS=0x...              # Keystone forwarder address
AUTHOR_ADDRESS=0x...                 # Expected workflow author
WORKFLOW_ID=0x...                    # Expected workflow ID (bytes32)
WORKFLOW_NAME=USDT_ILS               # Workflow name (max 10 chars)

# Optional - USDT Override (NOT recommended - uses auto-detection)
# USDT_ADDRESS=0x...

# RPC URLs (for convenience)
ETH_RPC_URL=https://eth.llamarpc.com
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
POLYGON_RPC_URL=https://polygon.llamarpc.com
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
BSC_RPC_URL=https://bsc-dataseed.binance.org

# Etherscan API Keys (for verification)
ETHERSCAN_API_KEY=...
POLYGONSCAN_API_KEY=...
ARBISCAN_API_KEY=...
BSCSCAN_API_KEY=...
```

### Load Environment

```bash
# Load environment variables
source .env

# Or export them manually
export PRIVATE_KEY=0x...
export ADMIN_ADDRESS=0x...
```

---

## Deployment Scenarios

## Scenario 1: Local Testing (Anvil)

**Use Case**: Local development and testing

### Step 1: Start Anvil

```bash
# Terminal 1
anvil
```

You'll see:
```
Available Accounts:
(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)
Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
...
```

### Step 2: Deploy Test System

```bash
# Terminal 2
cd smart_contract

# Deploy with mock USDT and test configuration
forge script script/DeployTest.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast \
  -vvv
```

**What happens:**
- ✅ Deploys MockUSDT (6 decimals, 1B supply)
- ✅ Deploys PriceFeedReceiver
- ✅ Configures test oracle settings
- ✅ Deploys LocalCurrencyToken (EGPd)
- ✅ Runs test mint and redeem

**Expected Output:**
```
=== Test Deployment (with Mock USDT) ===
Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

1. Deploying Mock USDT...
   Mock USDT deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
   USDT Balance: 1000000000000000

2. Deploying PriceFeedReceiver...
   PriceFeedReceiver deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3

3. Configuring PriceFeedReceiver...
   Added forwarder: 0x1234567890123456789012345678901234567890
   ...

4. Deploying LocalCurrencyToken (EGPd)...
   LocalCurrencyToken deployed at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

=== Testing Basic Functionality ===
5. Testing mint function...
   Minted: 50000
   Collateral: 1000

6. Testing redeem function...
   Redeemed: 25000
   Received USDT: 500

Test deployment successful!
```

### Step 3: Interact with Deployed Contracts

```bash
# Get deployed addresses from output above
MOCK_USDT=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
STABLECOIN=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

# Check balances
cast call $STABLECOIN "totalSupply()(uint256)" --rpc-url http://localhost:8545

# Mint more tokens
cast send $MOCK_USDT "approve(address,uint256)" $STABLECOIN 1000000000 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8545

cast send $STABLECOIN "mint(uint256)" 1000000000 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8545
```

---

## Scenario 2: Testnet Deployment (Sepolia)

**Use Case**: Pre-production testing with real network conditions

### Step 1: Configure Environment

```bash
# .env
PRIVATE_KEY=0x...                    # YOUR testnet private key
ADMIN_ADDRESS=0x...                  # YOUR admin address
CURRENCY_NAME="Palestinian Shekel Digital"
CURRENCY_SYMBOL="PLSd"
INITIAL_RATE=3223000                 # 3.223 ILS per USDT

# Optional Chainlink CRE
FORWARDER_ADDRESS=0x...
WORKFLOW_ID=0x...
```

### Step 2: Get Testnet ETH

Get Sepolia ETH from faucets:
- https://sepoliafaucet.com
- https://www.alchemy.com/faucets/ethereum-sepolia
- https://faucet.quicknode.com/ethereum/sepolia

### Step 3: Test on Fork First

```bash
# Test deployment on Sepolia fork before real deployment
forge test --match-contract ForkTest \
  --fork-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  -vv
```

### Step 4: Deploy to Sepolia

```bash
# Load environment
source .env

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

**What happens:**
- ✅ Detects Sepolia network (Chain ID: 11155111)
- ✅ Finds USDT at `0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0`
- ✅ Deploys PriceFeedReceiver
- ✅ Deploys LocalCurrencyToken with real USDT
- ✅ Verifies contracts on Etherscan

**Expected Output:**
```
=== StableCoin Deployment ===
Network: Sepolia
Chain ID: 11155111
Admin Address: 0x...
Initial Rate: 3223000
Currency: Palestinian Shekel Digital

Using existing USDT at: 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0

Deploying PriceFeedReceiver...
PriceFeedReceiver deployed at: 0x...

Deploying LocalCurrencyToken...
LocalCurrencyToken deployed at: 0x...

=== Deployment Summary ===
PriceFeedReceiver: 0x...
LocalCurrencyToken: 0x...
...
Deployment complete!
```

### Step 5: Verify on Etherscan

Visit: https://sepolia.etherscan.io/address/YOUR_CONTRACT_ADDRESS

Should show:
- ✅ Contract verified
- ✅ Source code visible
- ✅ Read/Write functions available

### Step 6: Manual Testing

```bash
# Get Sepolia USDT from faucet (if available)
# Or swap some Sepolia ETH for USDT on Uniswap testnet

# Approve USDT
cast send 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0 \
  "approve(address,uint256)" \
  YOUR_STABLECOIN_ADDRESS \
  1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY

# Mint stablecoins
cast send YOUR_STABLECOIN_ADDRESS \
  "mint(uint256)" \
  1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY

# Check balance
cast call YOUR_STABLECOIN_ADDRESS \
  "balanceOf(address)(uint256)" \
  YOUR_ADDRESS \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
```

---

## Scenario 3: Mainnet Deployment

**Use Case**: Production deployment

### ⚠️ Pre-Deployment Checklist

- [ ] All tests passing: `forge test`
- [ ] Fork tests successful on target network
- [ ] Testnet deployment successful and tested
- [ ] Security audit completed
- [ ] Admin keys secured (hardware wallet recommended)
- [ ] Multisig setup for admin (if applicable)
- [ ] Emergency pause procedure documented
- [ ] Monitoring and alerts configured
- [ ] Sufficient ETH for gas fees
- [ ] Backup of all deployment scripts and .env

### Step 1: Final Testing on Mainnet Fork

```bash
# Test on mainnet fork
forge test --match-contract ForkTest \
  --fork-url https://eth.llamarpc.com \
  -vv

# Expected: All tests pass with real USDT
```

### Step 2: Deploy to Ethereum Mainnet

```bash
# IMPORTANT: Double-check everything!
source .env

# Verify settings
echo "Admin Address: $ADMIN_ADDRESS"
echo "Currency: $CURRENCY_NAME ($CURRENCY_SYMBOL)"
echo "Initial Rate: $INITIAL_RATE"
echo "Continue? (Ctrl+C to cancel)"
read

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url https://eth.llamarpc.com \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv \
  --slow  # Add delay between transactions for safety
```

**Expected Gas Costs:**
- PriceFeedReceiver: ~800k gas (~$10-50 depending on gas price)
- LocalCurrencyToken: ~3.5M gas (~$50-250 depending on gas price)
- **Total**: ~4.3M gas (~$60-300)

### Step 3: Verify Deployment

```bash
# Save contract addresses
PRICE_FEED=0x...  # From deployment output
STABLECOIN=0x...  # From deployment output

# Verify on Etherscan
echo "PriceFeedReceiver: https://etherscan.io/address/$PRICE_FEED"
echo "StableCoin: https://etherscan.io/address/$STABLECOIN"

# Check deployment
cast call $STABLECOIN "name()(string)" --rpc-url https://eth.llamarpc.com
cast call $STABLECOIN "symbol()(string)" --rpc-url https://eth.llamarpc.com
cast call $STABLECOIN "usdt()(address)" --rpc-url https://eth.llamarpc.com
```

Expected:
```
Palestinian Shekel Digital
PLSd
0xdAC17F958D2ee523a2206206994597C13D831ec7
```

### Step 4: Configure Oracle (if using Chainlink CRE)

```bash
# Enable oracle mode
cast send $STABLECOIN "pause()" \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com

cast send $STABLECOIN "toggleUseOracle()" \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com

cast send $STABLECOIN "unpause()" \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com
```

### Step 5: Set Fees (if desired)

```bash
# Set 0.5% mint fee
cast send $STABLECOIN "setMintFee(uint256)" 50 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com

# Set 0.5% redeem fee
cast send $STABLECOIN "setRedeemFee(uint256)" 50 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com
```

### Step 6: Transfer Admin (Optional)

```bash
# If using multisig or different admin
ADMIN_ROLE=$(cast keccak "ADMIN_ROLE()")

# Grant role to new admin
cast send $STABLECOIN "grantRole(bytes32,address)" \
  $ADMIN_ROLE \
  NEW_ADMIN_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com

# Renounce deployer role (CAREFUL!)
# cast send $STABLECOIN "renounceRole(bytes32,address)" \
#   $ADMIN_ROLE \
#   YOUR_ADDRESS \
#   --private-key $PRIVATE_KEY \
#   --rpc-url https://eth.llamarpc.com
```

---

## Multi-Network Deployment

### Deploy to All Networks

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
        --etherscan-api-key "$api_key" \
        -vvv

    echo ""
    sleep 10  # Wait between deployments
done
```

---

## Post-Deployment

### Monitor Deployment

```bash
# Watch for first mint
cast logs --address $STABLECOIN \
  --rpc-url https://eth.llamarpc.com \
  "Minted(address,uint256,uint256,uint256)"

# Check collateral
cast call $STABLECOIN "getTotalCollateral()(uint256)" \
  --rpc-url https://eth.llamarpc.com

# Check total supply
cast call $STABLECOIN "totalSupply()(uint256)" \
  --rpc-url https://eth.llamarpc.com
```

### Set Up Monitoring

1. **Etherscan Alerts**: Watch for large transfers
2. **Collateral Ratio**: Monitor via `getInfo()`
3. **Oracle Updates**: Track price feed updates
4. **Fee Collection**: Monitor `totalFeesCollected()`

---

## Troubleshooting

### Issue: Deployment fails with "insufficient funds"

```bash
# Check deployer balance
cast balance $ADMIN_ADDRESS --rpc-url $RPC_URL

# Estimate gas cost
forge script script/Deploy.s.sol --rpc-url $RPC_URL --estimate-only
```

### Issue: Verification fails

```bash
# Manual verification
forge verify-contract \
  --chain-id CHAIN_ID \
  --constructor-args $(cast abi-encode "constructor(address,string,string,uint256,address,address)" ...) \
  CONTRACT_ADDRESS \
  src/StableCoin.sol:LocalCurrencyToken \
  $ETHERSCAN_API_KEY
```

### Issue: USDT not found

```bash
# Check current chain
cast chain-id --rpc-url $RPC_URL

# Manually set USDT address
export USDT_ADDRESS=0x...
```

---

## Summary

### Quick Commands Reference

```bash
# Local
anvil
forge script script/DeployTest.s.sol --rpc-url http://localhost:8545 --broadcast

# Testnet
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Mainnet
forge script script/Deploy.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify

# Interact
cast send $CONTRACT "functionName(args)" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
cast call $CONTRACT "viewFunction()(returnType)" --rpc-url $RPC_URL
```

### Deployed Contract Addresses

Keep a record:
```
Network: Ethereum Mainnet
PriceFeedReceiver: 0x...
LocalCurrencyToken: 0x...
Deployment Date: ...
Deployer: 0x...
Admin: 0x...
```

---

**🎉 Deployment Complete!**

Your stablecoin system is now live and ready to use.
