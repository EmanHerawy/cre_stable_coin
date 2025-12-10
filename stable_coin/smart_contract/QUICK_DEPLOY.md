# Quick Deployment Reference

## ✅ Issue Fixed

**Problem**: Deployment was failing with `OwnableUnauthorizedAccount` error because:
- PriceFeedReceiver was deployed with `admin` as owner
- But `deployer` was trying to configure it
- Only owner can call configuration functions

**Solution**:
- Deploy PriceFeedReceiver with deployer as initial owner
- Configure it
- Transfer ownership to admin address at the end

## 🚀 Deploy Now

### Option 1: Local Testing

```bash
# Terminal 1
anvil

# Terminal 2
forge script script/DeployTest.s.sol --rpc-url http://localhost:8545 --broadcast -vvv
```

### Option 2: Sepolia Testnet

```bash
# Set environment (if not already set)
export PRIVATE_KEY=0x...
export ADMIN_ADDRESS=0x...

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

### Option 3: Mainnet

```bash
# Deploy to Ethereum
forge script script/Deploy.s.sol \
  --rpc-url https://eth.llamarpc.com \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

## 📝 What Changed

### Before (Broken)
```solidity
// Deploy with admin as owner
PriceFeedReceiver priceFeedReceiver = new PriceFeedReceiver(config.admin);

// Try to configure (FAILS - deployer is not owner)
priceFeedReceiver.addKeystoneForwarder(forwarder);
```

### After (Fixed)
```solidity
// 1. Deploy with deployer as owner
PriceFeedReceiver priceFeedReceiver = new PriceFeedReceiver(deployer);

// 2. Configure (WORKS - deployer IS owner)
priceFeedReceiver.addKeystoneForwarder(forwarder);

// 3. Transfer to admin if different
if (config.admin != deployer) {
    priceFeedReceiver.transferOwnership(config.admin);
}
```

## ✨ Expected Output

```
=== StableCoin Deployment ===
Network: Sepolia
Chain ID: 11155111
Admin Address: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
Initial Rate: 50000000
Currency: Egyptian Pound Digital

Using existing USDT at: 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0

Deploying PriceFeedReceiver...
PriceFeedReceiver deployed at: 0x...

Adding Workflow Name: 0x5553445f454750000000
Transferring PriceFeedReceiver ownership to: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38

Deploying LocalCurrencyToken...
LocalCurrencyToken deployed at: 0x...

=== Deployment Summary ===
PriceFeedReceiver: 0x...
LocalCurrencyToken: 0x...

Deployment complete! ✅
```

## 🔑 Key Points

1. **Deployer vs Admin**: They can be the same or different addresses
   - If same: No ownership transfer needed
   - If different: Ownership automatically transferred after configuration

2. **Why This Pattern**:
   - Deployer needs to configure contracts during deployment
   - Admin gets final ownership for long-term management
   - Separates deployment responsibilities from ongoing governance

3. **Security**: Both deployer and admin should be secure addresses
   - Deployer: Can be a hot wallet (used once for deployment)
   - Admin: Should be a hardware wallet or multisig (long-term control)

## 📋 Post-Deployment Checklist

After successful deployment:

- [ ] Save contract addresses
- [ ] Verify on block explorer (should auto-verify with `--verify` flag)
- [ ] Test basic functionality:
  ```bash
  # Check admin role
  cast call $STABLECOIN "hasRole(bytes32,address)(bool)" \
    $(cast keccak "ADMIN_ROLE()") \
    $ADMIN_ADDRESS \
    --rpc-url $RPC_URL

  # Check PriceFeedReceiver owner
  cast call $PRICE_FEED "owner()(address)" --rpc-url $RPC_URL
  ```
- [ ] Configure fees (if needed)
- [ ] Enable oracle (if using Chainlink CRE)
- [ ] Set up monitoring

## 🆘 Troubleshooting

### Still Getting OwnableUnauthorizedAccount?

```bash
# Check who's deploying
cast wallet address --private-key $PRIVATE_KEY

# Check admin address
echo $ADMIN_ADDRESS

# They should match your .env configuration
```

### Need to Use Different Admin?

Update your `.env`:
```bash
ADMIN_ADDRESS=0xYourNewAdminAddress
```

### Want Deployer to Stay as Owner?

Set admin to deployer address:
```bash
export ADMIN_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
```

## 📚 Full Documentation

For complete deployment guide, see:
- **DEPLOYMENT_GUIDE.md** - Complete deployment instructions
- **NETWORK_DEPLOYMENT.md** - Network-specific guides
- **README.md** - Project overview

---

**Ready to deploy! 🚀**

The issue is fixed and you can now deploy to any network.
