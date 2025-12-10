# Single Feed Architecture

## What Changed

### ✅ PriceFeedReceiver - Now Handles ONE Coin Only

**Before:** Could handle multiple feeds with different feedIds
```solidity
mapping(bytes32 feedId => StoredFeedReport) internal s_feedReports;
function getPrice(bytes32 feedId) returns (uint224, uint32)
```

**After:** Handles single feed only
```solidity
uint224 public latestPrice;
uint32 public latestTimestamp;
function getPrice() returns (uint224, uint32) // No feedId parameter!
```

---

## Architecture Overview

```
┌──────────────────────────────────────┐
│ USD/EGP StableCoin                   │
│  - Egyptian Pound Digital            │
└──────────────────────────────────────┘
              ↓ queries price
┌──────────────────────────────────────┐
│ PriceFeedReceiver #1                 │
│  - Configured for USD/EGP only       │
│  - latestPrice: 50.00                │
└──────────────────────────────────────┘
              ↓ receives from
┌──────────────────────────────────────┐
│ Chainlink CRE - USD/EGP Feed         │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ USD/NGN StableCoin                   │
│  - Nigerian Naira Digital            │
└──────────────────────────────────────┘
              ↓ queries price
┌──────────────────────────────────────┐
│ PriceFeedReceiver #2                 │
│  - Configured for USD/NGN only       │
│  - latestPrice: 1500.00              │
└──────────────────────────────────────┘
              ↓ receives from
┌──────────────────────────────────────┐
│ Chainlink CRE - USD/NGN Feed         │
└──────────────────────────────────────┘
```

**Key:** One PriceFeedReceiver per currency pair!

---

## Benefits of Single Feed Design

### 1. **Simplicity**
- No feedId confusion
- Clear 1:1 relationship
- Easier to understand and audit

### 2. **Gas Efficiency**
```solidity
// Before: Storage read from mapping
s_feedReports[feedId].price  // SLOAD from mapping

// After: Direct storage read
latestPrice  // SLOAD from single slot
```
**~2,100 gas saved per price query!**

### 3. **Security**
- No risk of wrong feedId
- Single source of truth
- Simpler validation logic

### 4. **Deployment Pattern**
```solidity
// Deploy receiver for each currency
PriceFeedReceiver egpReceiver = new PriceFeedReceiver(admin);
PriceFeedReceiver ngnReceiver = new PriceFeedReceiver(admin);

// Configure each independently
egpReceiver.addKeystoneForwarder(forwarderAddress);
ngnReceiver.addKeystoneForwarder(forwarderAddress);

// Deploy StableCoins
StableCoin egpToken = new StableCoin(
    usdt, "EGP Digital", "EGPd", 50e6, admin,
    address(egpReceiver) // ← Dedicated receiver
);

StableCoin ngnToken = new StableCoin(
    usdt, "NGN Digital", "NGNd", 1500e6, admin,
    address(ngnReceiver) // ← Different receiver
);
```

---

## Changes in PriceFeedReceiver

### Storage (lines 30-32)
```solidity
// REMOVED
mapping(bytes32 feedId => StoredFeedReport) internal s_feedReports;
struct ReceivedFeedReport { bytes32 feedId; ... }

// ADDED
uint224 public latestPrice;
uint32 public latestTimestamp;
```

### _processReport() (lines 107-117)
```solidity
// BEFORE
ReceivedFeedReport[] memory feeds = abi.decode(report, (ReceivedFeedReport[]));
for (uint256 i = 0; i < feeds.length; ++i) {
    s_feedReports[feeds[i].feedId] = ...;
}

// AFTER
(uint224 price, uint32 timestamp) = abi.decode(report, (uint224, uint32));
latestPrice = price;
latestTimestamp = timestamp;
```

### getPrice() (lines 122-127)
```solidity
// BEFORE
function getPrice(bytes32 feedId) external view returns (uint224, uint32) {
    StoredFeedReport memory report = s_feedReports[feedId];
    ...
}

// AFTER
function getPrice() external view returns (uint224, uint32) {
    if (latestTimestamp == 0) revert NoDataPresent();
    return (latestPrice, latestTimestamp);
}
```

---

## Changes in StableCoin

### Removed feedId (line 43)
```solidity
// REMOVED
bytes32 public feedId;
```

### Constructor (lines 93-100)
```solidity
// BEFORE
constructor(
    ...,
    address priceFeedReceiverAddress,
    bytes32 _feedId  // ❌ Removed
)

// AFTER
constructor(
    ...,
    address priceFeedReceiverAddress  // ✅ Just the receiver
)
```

### _getOracleRate() (lines 168-174)
```solidity
// BEFORE
if (address(priceFeedReceiver) == address(0) || feedId == bytes32(0)) {
    return manualRate;
}
try priceFeedReceiver.getPrice(feedId) returns (...) {

// AFTER
if (address(priceFeedReceiver) == address(0)) {
    return manualRate;
}
try priceFeedReceiver.getPrice() returns (...) {
```

### getLastPriceUpdate() (lines 146-152)
```solidity
// BEFORE
if (useOracle && address(priceFeedReceiver) != address(0) && feedId != bytes32(0)) {
    (, uint32 priceTimestamp) = priceFeedReceiver.getPrice(feedId);

// AFTER
if (useOracle && address(priceFeedReceiver) != address(0)) {
    (, uint32 priceTimestamp) = priceFeedReceiver.getPrice();
```

---

## Deployment Example

### Step 1: Deploy PriceFeedReceiver
```solidity
// For Egyptian Pound
PriceFeedReceiver egpReceiver = new PriceFeedReceiver(adminAddress);

// Configure security
egpReceiver.addKeystoneForwarder(0x...);
egpReceiver.addExpectedWorkflowId(0x...);
egpReceiver.addExpectedAuthor(0x...);
egpReceiver.addExpectedWorkflowName("USD_EGP");
```

### Step 2: Deploy StableCoin
```solidity
StableCoin egpToken = new StableCoin(
    0x... /* USDT */,
    "Egyptian Pound Digital",
    "EGPd",
    50e6,  /* 50 EGP per USDT */
    adminAddress,
    address(egpReceiver)  // ← Connected to dedicated receiver
);
```

### Step 3: Chainlink CRE Workflow Sends Price
```javascript
// CRE workflow sends report to egpReceiver
report = abi.encode(
    uint224(5000000000),  // 50.00 EGP (8 decimals)
    uint32(block.timestamp)
);
// egpReceiver.onReport(..., report) called by Chainlink
```

### Step 4: StableCoin Queries Price
```solidity
// User mints tokens
egpToken.mint(1000e6); // 1000 USDT

// Internally:
uint256 rate = _getOracleRate();
  → priceFeedReceiver.getPrice() // No feedId!
  → returns (5000000000, 1234567890)
  → converts to 50e6 (6 decimals)
// User receives 50,000 EGPd tokens
```

---

## Migration from Multi-Feed Design

If you already deployed with multi-feed design:

### Option 1: Deploy New Receivers (Recommended)
```solidity
// Old (multi-feed) - deprecated
PriceFeedReceiver oldReceiver = 0x1234...;

// New (single-feed) for each currency
PriceFeedReceiver egpReceiver = new PriceFeedReceiver(admin);
PriceFeedReceiver ngnReceiver = new PriceFeedReceiver(admin);

// Deploy new StableCoins
StableCoin egpTokenV2 = new StableCoin(..., address(egpReceiver));
StableCoin ngnTokenV2 = new StableCoin(..., address(ngnReceiver));
```

### Option 2: Keep Old for Backward Compatibility
```solidity
// Old contracts continue working
oldEgpToken.getPrice(feedIdEGP);

// New contracts use simpler interface
newEgpToken.getPrice(); // No feedId
```

---

## Why This Is Better

| Aspect | Multi-Feed | Single-Feed |
|--------|-----------|-------------|
| **Complexity** | High - manage feedIds | Low - just one price |
| **Gas Cost** | Higher mapping lookup | Lower direct read |
| **Error Risk** | Wrong feedId possible | No feedId confusion |
| **Code Size** | More complex | Simpler, cleaner |
| **Auditability** | Harder to track | Easy to audit |
| **Deployment** | One receiver, multiple feeds | One receiver per feed |

---

## Summary

**One PriceFeedReceiver = One Currency Pair = Simpler & Safer**

The architecture is now:
- ✅ Easier to understand
- ✅ Cheaper to use (gas)
- ✅ Harder to misconfigure
- ✅ Cleaner separation of concerns

Each currency gets its own dedicated price receiver! 🎯
