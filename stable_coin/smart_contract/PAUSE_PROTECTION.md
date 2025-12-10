# Pause Protection Strategy

## Functions That Require `whenPaused`

### ✅ **Critical Functions (Must Pause)**

These functions directly affect pricing or core protocol behavior and MUST require pause:

#### 1. **`updateManualRate()`** ✅ REQUIRES PAUSE
```solidity
function updateManualRate(uint256 newRate)
    external
    onlyRole(RATE_UPDATER_ROLE)
    whenPaused
```

**Why?**
- Changes the exchange rate users get
- Could cause unfair mint/redeem during rate change
- Example attack:
  ```
  User calls mint(1000 USDT) at rate 50 EGP
  Admin calls updateManualRate(60) mid-transaction
  User gets tokens at wrong rate
  ```

#### 2. **`setPriceFeedReceiver()`** ✅ REQUIRES PAUSE
```solidity
function setPriceFeedReceiver(address newPriceFeedReceiver)
    external
    onlyRole(ADMIN_ROLE)
    whenPaused
```

**Why?**
- Changes where prices come from
- Could cause sudden price jumps
- Example: Old receiver = 50 EGP, New receiver = 60 EGP

#### 3. **`setUseOracle()`** ✅ REQUIRES PAUSE
```solidity
function setUseOracle(bool _useOracle)
    external
    onlyRole(ADMIN_ROLE)
    whenPaused
```

**Why?**
- Switches between oracle and manual pricing
- Prices could differ significantly
- Example: Oracle = 50 EGP, Manual = 55 EGP

---

### ⚠️ **Semi-Critical Functions (Can Stay Live)**

These functions don't directly affect pricing but control access/limits:

#### 4. **`setMaxPriceAge()`** ⚠️ NO PAUSE NEEDED
```solidity
function setMaxPriceAge(uint256 newAge)
    external
    onlyRole(ADMIN_ROLE)
    // NO whenPaused - safe to change live
```

**Why Safe?**
- Only affects staleness check
- Making it more strict = more conservative (safe)
- Making it less strict = less conservative but admin's choice
- Doesn't change prices, just validation threshold

#### 5. **`setMinDeposit()`** ⚠️ NO PAUSE NEEDED
```solidity
function setMinDeposit(uint256 newMin)
    external
    onlyRole(ADMIN_ROLE)
    // NO whenPaused - safe to change live
```

**Why Safe?**
- Only prevents very small deposits
- Doesn't affect existing transactions
- User transactions simply revert if below minimum
- No financial loss possible

#### 6. **`setMinWithdrawal()`** ⚠️ NO PAUSE NEEDED
```solidity
function setMinWithdrawal(uint256 newMin)
    external
    onlyRole(ADMIN_ROLE)
    // NO whenPaused - safe to change live
```

**Why Safe?**
- Only prevents very small withdrawals
- Doesn't affect existing transactions
- User transactions simply revert if below minimum
- No financial loss possible

---

## Comparison Table

| Function | Requires Pause? | Impact | Risk if Not Paused |
|----------|----------------|--------|-------------------|
| `updateManualRate()` | ✅ YES | Direct pricing | High - unfair rates |
| `setPriceFeedReceiver()` | ✅ YES | Price source | High - sudden price change |
| `setUseOracle()` | ✅ YES | Pricing mode | High - price inconsistency |
| `setMaxPriceAge()` | ❌ NO | Staleness check | Low - just validation |
| `setMinDeposit()` | ❌ NO | Minimum limits | None - tx reverts safely |
| `setMinWithdrawal()` | ❌ NO | Minimum limits | None - tx reverts safely |

---

## Attack Scenarios Prevented

### Scenario 1: Rate Manipulation (PREVENTED ✅)
**Without `whenPaused`:**
```solidity
// Block N
User: mint(1000 USDT) at rate 50 EGP → gets 50,000 EGPd

// Block N (same block!)
Admin: updateManualRate(60 EGP)

// Block N
User2: mint(1000 USDT) at rate 60 EGP → gets 60,000 EGPd

// Unfair! Same block, different rates
```

**With `whenPaused`:**
```solidity
// Admin must pause first
Admin: pause()
// All mint/redeem stop
Admin: updateManualRate(60 EGP)
Admin: unpause()
// Everyone gets same rate from this point
```

### Scenario 2: Oracle Switch Front-Running (PREVENTED ✅)
**Without `whenPaused`:**
```solidity
// Oracle = 50 EGP, Manual = 55 EGP
User sees admin tx: setUseOracle(false) in mempool
User front-runs: mint(1000 USDT) at 50 EGP
Admin tx executes: switches to manual 55 EGP
User back-runs: redeem immediately at 55 EGP
// Instant 10% profit!
```

**With `whenPaused`:**
```solidity
Admin: pause()
// No mints/redeems possible
Admin: setUseOracle(false)
Admin: unpause()
// No arbitrage possible
```

### Scenario 3: Minimum Changes (SAFE WITHOUT PAUSE ✅)
**Without `whenPaused`:**
```solidity
User: mint(0.5 USDT) - in mempool
Admin: setMinDeposit(1 USDT)
User tx executes: reverts with DepositBelowMinimum
// User just retries with 1 USDT, no harm done
```

---

## Operational Workflow

### Updating Pricing Parameters
```solidity
// 1. Pause
stableCoin.pause();

// 2. Update pricing
stableCoin.updateManualRate(55e6);
// OR
stableCoin.setPriceFeedReceiver(newReceiver);
// OR
stableCoin.setUseOracle(false);

// 3. Announce to users (wait period optional)
// "System will resume in 5 minutes with new rate"

// 4. Unpause
stableCoin.unpause();
```

### Updating Non-Pricing Parameters (No Pause Needed)
```solidity
// Can do anytime, no pause needed
stableCoin.setMinDeposit(2e6);
stableCoin.setMinWithdrawal(2e6);
stableCoin.setMaxPriceAge(7200);
```

---

## Gas Considerations

### Functions With `whenPaused`
```solidity
// More expensive (extra SLOAD for pause check)
updateManualRate(50e6)
// Cost: ~3,000 gas for pause check + function logic
```

### Functions Without `whenPaused`
```solidity
// Cheaper (no pause check)
setMinDeposit(1e6)
// Cost: just function logic
```

**Decision:** Worth the extra gas for critical functions!

---

## Summary

### ✅ Require Pause (Pricing-Related):
1. `updateManualRate()` - Direct rate change
2. `setPriceFeedReceiver()` - Price source change
3. `setUseOracle()` - Pricing mode change

### ❌ No Pause Needed (Configuration):
1. `setMaxPriceAge()` - Just validation threshold
2. `setMinDeposit()` - Just access limit
3. `setMinWithdrawal()` - Just access limit

**Principle:** If it affects the price users get, it must pause. If it just validates/limits, no pause needed.

This protects users from unexpected mid-transaction parameter changes! 🛡️
