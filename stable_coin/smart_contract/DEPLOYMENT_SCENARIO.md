# Real-World Deployment Scenario

## Phase 1: Initial Launch (Manual Mode)
```solidity
// 1. Deploy StableCoin with manual rate
StableCoin egpToken = new StableCoin(
    usdtAddress,
    "Egyptian Pound Digital",
    "EGPd",
    50e6, // 50 EGP per USDT
    adminAddress
);

// 2. useOracle = false (default), uses manual rate
// 3. Launch to users with manual price updates
```

**Why?** Start simple, test in production, avoid oracle complexity initially.

---

## Phase 2: Deploy Price Feed (2 weeks later)
```solidity
// 1. Deploy PriceFeedReceiver
PriceFeedReceiver receiver = new PriceFeedReceiver(adminAddress);

// 2. Configure the receiver
receiver.addKeystoneForwarder(forwarderAddress);
receiver.addExpectedWorkflowId(workflowId);
receiver.addExpectedAuthor(authorAddress);

// 3. Connect to StableCoin
egpToken.setPriceFeedReceiver(address(receiver));
egpToken.setFeedId(0xabc123...); // USD/EGP feed ID
```

**Why?** Chainlink CRE integration takes time to setup and test.

---

## Phase 3: Switch to Oracle (After Testing)
```solidity
// Switch to oracle mode
egpToken.setUseOracle(true);
```

**Why?** Only enable after confirming feeds are working correctly.

---

## Phase 4: Emergency Scenario (Oracle Malfunction)
```solidity
// 1. Oracle provides stale/wrong data
// Monitor detects: lastPriceUpdate > 24 hours old

// 2. Admin immediately switches to manual
egpToken.setUseOracle(false);

// 3. Admin updates manual rate
egpToken.updateManualRate(51e6); // Current market rate

// 4. Users can continue trading safely
```

**Why?** Can't have users stuck unable to mint/redeem!

---

## Phase 5: Upgrade Receiver (Bug Fix)
```solidity
// 1. Bug found in PriceFeedReceiver v1
// 2. Deploy fixed version v2
PriceFeedReceiver receiverV2 = new PriceFeedReceiver(adminAddress);

// 3. Configure v2
receiverV2.addKeystoneForwarder(forwarderAddress);
// ... other configs

// 4. Switch to v2
egpToken.setPriceFeedReceiver(address(receiverV2));

// 5. Oracle continues working without interruption
```

**Why?** Smart contracts can have bugs, need upgrade path.

---

## Phase 6: Multi-Currency Support
```solidity
// Deploy second stablecoin for Nigerian Naira
StableCoin ngnToken = new StableCoin(
    usdtAddress,
    "Nigerian Naira Digital",
    "NGNd",
    1500e6, // 1500 NGN per USDT
    adminAddress
);

// Use SAME receiver, different feed ID
ngnToken.setPriceFeedReceiver(address(receiver));
ngnToken.setFeedId(0xdef456...); // USD/NGN feed ID
```

**Why?** One PriceFeedReceiver can serve multiple currencies!

---

## Without These Functions?

### ❌ Problems:
1. **No Oracle Support**: Stuck with manual rates forever
2. **No Upgrades**: Bug in receiver? Deploy entire StableCoin again (lose state!)
3. **No Emergency**: Oracle fails? System stops working
4. **No Testing**: Can't test in stages, must be perfect on day 1

### ✅ With These Functions:
1. Start simple, add complexity later
2. Upgrade components independently
3. Handle emergencies gracefully
4. Test in production safely
