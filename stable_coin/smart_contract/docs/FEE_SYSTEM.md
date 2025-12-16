# Fee Management System

## Overview

The StableCoin contract includes a configurable fee system to cover Chainlink CRE costs and protocol maintenance. Fees are collected in USDT during mint and redeem operations.

**Note**: The fee system is managed by the LocalCurrencyToken (StableCoin) contract, while exchange rate management is handled by the separate Converter contract. This separation of concerns provides better security and modularity.

## Features

### 1. **Configurable Fees**
- **Mint Fee**: Charged when users deposit USDT and receive local currency tokens
- **Redeem Fee**: Charged when users redeem local currency tokens for USDT
- Fees are set in basis points (bps): `100 = 1%`, `1000 = 10%`
- Maximum allowed fee: **10% (1000 bps)**

### 2. **Fee Collection**
- All fees are collected in **USDT**
- Fees are automatically tracked in `totalFeesToBeCollected`
- Fees are included in total collateral but excluded from net collateral

### 3. **Fee Withdrawal**
- Only ADMIN_ROLE can withdraw fees
- Fees can be withdrawn partially or fully
- Protected by reentrancy guard
- Emits `FeesWithdrawn` event for transparency

## How It Works

### Mint with Fee

```solidity
// User deposits 1000 USDT with 1% mint fee
User sends: 1000 USDT
Fee collected: 10 USDT (1%)
USDT used for minting: 990 USDT
Tokens received: 990 USDT * rate = 3,190.77 ILS tokens

// Fee stays in contract, tracked separately
totalFeesToBeCollected += 10 USDT
```

### Redeem with Fee

```solidity
// User redeems 3,190.77 ILS tokens with 0.5% redeem fee
Tokens burned: 3,190.77 ILS
USDT before fee: 990 USDT
Fee collected: 4.95 USDT (0.5%)
USDT sent to user: 985.05 USDT

// Fee stays in contract
totalFeesToBeCollected += 4.95 USDT
```

## Admin Functions

### Set Mint Fee
```solidity
function setMintFee(uint256 newFeeBps) external onlyRole(ADMIN_ROLE)
```
- **Parameter**: Fee in basis points (0-1000)
- **Example**: `setMintFee(100)` sets 1% mint fee
- **Reverts if**: Fee > 10% (1000 bps)

### Set Redeem Fee
```solidity
function setRedeemFee(uint256 newFeeBps) external onlyRole(ADMIN_ROLE)
```
- **Parameter**: Fee in basis points (0-1000)
- **Example**: `setRedeemFee(50)` sets 0.5% redeem fee
- **Reverts if**: Fee > 10% (1000 bps)

### Withdraw Fees
```solidity
function withdrawFees(address recipient, uint256 amount) external onlyRole(ADMIN_ROLE)
```
- **Parameters**:
  - `recipient`: Address to receive the USDT fees
  - `amount`: Amount of USDT to withdraw
- **Example**: `withdrawFees(treasury, 100e6)` withdraws 100 USDT to treasury
- **Reverts if**:
  - Amount > totalFeesToBeCollected
  - Recipient is zero address
  - Amount is zero

## View Functions

### Get Fee and Collateral Information
```solidity
function getInfo() external view returns (
    uint256 currentRate,
    uint256 totalSupply_,
    uint256 collateral,
    uint256 netCollateral,
    uint256 feesCollected,
    uint256 mintFee,
    uint256 redeemFee,
    address converterAddress
)
```

### Get Net Collateral
```solidity
function getNetCollateral() public view returns (uint256)
```
Returns the actual collateral backing tokens (excluding fees).

## Examples

### Example 1: Setting Up Fees for Chainlink CRE Costs

```solidity
// Admin sets 0.25% mint fee and 0.25% redeem fee
stableCoin.setMintFee(25);   // 0.25%
stableCoin.setRedeemFee(25); // 0.25%

// After 1 month of operations:
// - Total mints: 1,000,000 USDT
// - Total redeems: 800,000 USDT
// - Fees collected: (1M * 0.0025) + (800k * 0.0025) = 4,500 USDT

// Withdraw fees to pay for CRE costs
stableCoin.withdrawFees(treasuryAddress, 4_500e6);
```

### Example 2: User Journey with Fees

```solidity
// Setup: 1% mint fee, 0.5% redeem fee
// Rate: 1 USDT = 3.223 ILS

// User deposits 1000 USDT
// - Fee: 10 USDT
// - USDT for minting: 990 USDT
// - ILS received: 3,190.77 tokens

// Later, user redeems all tokens
// - ILS to redeem: 3,190.77
// - USDT before fee: 990 USDT
// - Fee: 4.95 USDT
// - USDT received: 985.05 USDT

// Net loss from fees: 14.95 USDT (1.495% total)
```

## Accounting

### Collateral Breakdown

```
Total USDT in Contract = Net Collateral + Fees Collected

Net Collateral = Amount backing minted tokens
Fees Collected = Accumulated fees available for withdrawal
```

### Collateral Ratio

The collateral ratio is calculated using **net collateral** (excluding fees):

```solidity
collateralRatio = (netCollateral * 10000) / requiredCollateral

// Should always be ~100% (10000 bps)
```

## Events

```solidity
event MintFeeUpdated(uint256 oldFee, uint256 newFee);
event RedeemFeeUpdated(uint256 oldFee, uint256 newFee);
event FeesWithdrawn(address indexed recipient, uint256 amount);
event Minted(address indexed user, uint256 usdtAmount, uint256 localCurrencyAmount, uint256 fee);
event Redeemed(address indexed user, uint256 localCurrencyAmount, uint256 usdtAmount, uint256 fee);
```

## Security Features

1. ✅ **Maximum fee cap**: 10% to prevent excessive fees
2. ✅ **Admin-only access**: Only ADMIN_ROLE can modify fees and withdraw
3. ✅ **Reentrancy protection**: withdrawFees uses nonReentrant modifier
4. ✅ **Event emission**: All fee operations emit events for transparency
5. ✅ **Separate accounting**: Fees tracked separately from user collateral
6. ✅ **Cannot withdraw more than collected**: Prevents draining user funds

## Testing

Comprehensive test suite in `test/FeeManagement.t.sol`:

```bash
forge test --match-contract FeeManagementTest
```

Tests cover:
- ✅ Fee configuration (set/update)
- ✅ Mint with fees
- ✅ Redeem with fees
- ✅ Fee withdrawal (full and partial)
- ✅ Access control
- ✅ Edge cases
- ✅ Event emission
- ✅ Integration tests

## Use Cases

### 1. **Covering Chainlink CRE Costs**
```solidity
// Set fees to cover estimated monthly CRE costs
uint256 estimatedMonthlyCost = 500e6; // 500 USDT
uint256 estimatedMonthlyVolume = 100_000e6; // 100k USDT

// Calculate required fee: 500/100000 = 0.5%
stableCoin.setMintFee(50);  // 0.5%
stableCoin.setRedeemFee(0); // No redeem fee

// At end of month, withdraw for CRE payment
stableCoin.withdrawFees(crePaymentAddress, stableCoin.totalFeesToBeCollected());
```

### 2. **Protocol Revenue**
```solidity
// Set sustainable fees for protocol operation
stableCoin.setMintFee(10);   // 0.1%
stableCoin.setRedeemFee(10); // 0.1%

// Withdraw to treasury quarterly
stableCoin.withdrawFees(protocolTreasury, feesForQuarter);
```

### 3. **Dynamic Fee Adjustment**
```solidity
// Adjust fees based on market conditions
if (highDemand) {
    stableCoin.setMintFee(100);  // 1% during high demand
} else {
    stableCoin.setMintFee(25);   // 0.25% during normal times
}
```

## Gas Optimization

- Fees calculated inline (no external calls)
- Simple arithmetic (no complex math)
- Events for off-chain tracking
- Minimal storage updates

## Decimal Precision

All fees are calculated in USDT (6 decimals):
- Fee amount = `(amount * feeBps) / 10000`
- No precision loss for fees >= 0.01% (1 bps)
- Rounding always favors the protocol (fee rounded down)

## Best Practices

1. **Start with low fees**: Begin with 0.1-0.5% and adjust based on actual costs
2. **Monitor fee collection**: Regularly check `totalFeesToBeCollected`
3. **Transparent communication**: Inform users of fee changes
4. **Regular withdrawals**: Don't let fees accumulate excessively
5. **Fee budgeting**: Calculate fees needed to cover CRE costs
