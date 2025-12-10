# Deployment Guide

This guide explains how to deploy the StableCoin system (PriceFeedReceiver + LocalCurrencyToken) to various networks.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Private key with sufficient ETH for gas
- RPC URL for target network
- Etherscan API key (for verification)

## Quick Start

### 1. Install Dependencies

```bash
forge install
```

### 2. Run Tests

```bash
forge test
```

All tests should pass (55 tests):
- PriceFeedReceiver: 15 tests
- LocalCurrencyToken: 40 tests

### 3. Dry Run (Local Testing)

Test the deployment locally using Anvil:

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Run deployment test
forge script script/DeployTest.s.sol:DeployTestScript --fork-url http://localhost:8545 -vvv
```

This will:
- Deploy a mock USDT token
- Deploy PriceFeedReceiver
- Deploy LocalCurrencyToken
- Configure the system
- Test mint and redeem functions

## Production Deployment

### Step 1: Configure Environment

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```bash
# Required
PRIVATE_KEY=0x...                                    # Deployer private key
USDT_ADDRESS=0xdAC17F958D2ee523a2206206994597C13D831ec7  # USDT contract
ADMIN_ADDRESS=0x...                                  # Admin address

# Chainlink CRE Configuration (optional - can configure later)
FORWARDER_ADDRESS=0x...                              # Keystone forwarder
AUTHOR_ADDRESS=0x...                                 # Workflow author
WORKFLOW_ID=0x...                                    # Workflow ID
WORKFLOW_NAME=USD_EGP                                # Workflow name

# Currency Configuration
CURRENCY_NAME="Egyptian Pound Digital"
CURRENCY_SYMBOL=EGPd
INITIAL_RATE=50000000                                # 50 EGP per USDT (6 decimals)

# Network RPC
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY

# Verification
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```

### Step 2: Dry Run on Testnet

Test on Sepolia testnet first:

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --slow \
  -vvvv
```

Review the output carefully. If everything looks good, proceed with broadcasting.

### Step 3: Deploy to Testnet

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow \
  -vvvv
```

### Step 4: Deploy to Mainnet

**⚠️ WARNING: Review all configuration carefully before mainnet deployment!**

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow \
  -vvvv
```

## Post-Deployment Configuration

After deployment, you may need to configure additional settings:

### 1. Configure PriceFeedReceiver (if not done during deployment)

```solidity
// Add Keystone forwarder
priceFeedReceiver.addKeystoneForwarder(forwarderAddress);

// Add workflow ID
priceFeedReceiver.addExpectedWorkflowId(workflowId);

// Add expected author
priceFeedReceiver.addExpectedAuthor(authorAddress);

// Add workflow name
priceFeedReceiver.addExpectedWorkflowName(bytes10("USD_EGP"));
```

### 2. Grant Additional Roles

```solidity
// Grant RATE_UPDATER_ROLE to additional addresses
stableCoin.grantRole(RATE_UPDATER_ROLE, updaterAddress);

// Grant PAUSER_ROLE to additional addresses
stableCoin.grantRole(PAUSER_ROLE, pauserAddress);
```

### 3. Adjust Parameters

```solidity
// Update minimum deposit/withdrawal
stableCoin.setMinDeposit(2e6);  // 2 USDT
stableCoin.setMinWithdrawal(2e6);

// Update max price age
stableCoin.setMaxPriceAge(7200);  // 2 hours
```

## Deployment Verification

After deployment, verify the contracts are configured correctly:

```bash
forge script script/Deploy.s.sol:DeployScript \
  --sig "verify(address,address)" \
  <PRICE_FEED_RECEIVER_ADDRESS> \
  <STABLE_COIN_ADDRESS> \
  --rpc-url $SEPOLIA_RPC_URL
```

Check:
- ✅ PriceFeedReceiver has forwarders configured
- ✅ PriceFeedReceiver has workflow IDs configured
- ✅ StableCoin is connected to correct PriceFeedReceiver
- ✅ StableCoin has correct USDT address
- ✅ Initial rate is correct
- ✅ Admin roles are assigned correctly

## Network Addresses

### Mainnet

- **USDT**: `0xdAC17F958D2ee523a2206206994597C13D831ec7`

### Sepolia Testnet

- **USDT**: `0x7169D38820dfd117C3FA1f22a697dBA58d90BA06` (Aave Faucet USDT)

## Operational Procedures

### Updating the Exchange Rate

When you need to update the manual rate:

```bash
# 1. Pause the contract
cast send $STABLE_COIN_ADDRESS "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 2. Update the rate (e.g., 55 EGP per USDT)
cast send $STABLE_COIN_ADDRESS "updateManualRate(uint256)" 55000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 3. Unpause the contract
cast send $STABLE_COIN_ADDRESS "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Switching Between Oracle and Manual Rate

```bash
# Pause first
cast send $STABLE_COIN_ADDRESS "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Toggle oracle mode
cast send $STABLE_COIN_ADDRESS "toggleUseOracle()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Unpause
cast send $STABLE_COIN_ADDRESS "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Updating PriceFeedReceiver Address

```bash
# Pause first
cast send $STABLE_COIN_ADDRESS "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Update receiver
cast send $STABLE_COIN_ADDRESS "setPriceFeedReceiver(address)" $NEW_RECEIVER --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Unpause
cast send $STABLE_COIN_ADDRESS "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Gas Estimates

Based on testnet deployment:

| Operation | Gas Used |
|-----------|----------|
| Deploy PriceFeedReceiver | ~1,400,000 |
| Deploy LocalCurrencyToken | ~3,100,000 |
| Configure PriceFeedReceiver | ~300,000 |
| **Total Deployment** | **~4,800,000** |
| Mint | ~127,000 |
| Redeem | ~66,000 |
| Update Manual Rate | ~55,000 |

**Estimated deployment cost**: ~0.014 ETH (at 3 gwei gas price)

## Security Considerations

1. **Private Key Security**: Never commit `.env` file with real private keys
2. **Admin Address**: Use a multisig wallet for production admin
3. **Rate Updates**: Always pause before updating critical parameters
4. **Oracle Configuration**: Verify Chainlink CRE addresses before deployment
5. **Testing**: Always deploy to testnet first

## Troubleshooting

### "Insufficient funds for gas"
- Ensure deployer account has enough ETH for gas

### "Invalid address"
- Verify all addresses in `.env` are checksummed correctly
- Use `cast --to-checksum-address <address>` to get correct format

### "Contract verification failed"
- Ensure Etherscan API key is correct
- Try manual verification using Etherscan UI
- Check constructor arguments match deployment

### Tests failing
- Run `forge clean` and rebuild
- Ensure dependencies are installed: `forge install`
- Check Solidity version matches (0.8.20+)

## Support

For issues or questions:
1. Check this documentation
2. Review test files for usage examples
3. Consult architecture documentation (SINGLE_FEED_ARCHITECTURE.md, PAUSE_PROTECTION.md)
