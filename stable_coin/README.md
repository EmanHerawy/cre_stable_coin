
# USDT/ILS Price Feed Workflow

This Chainlink CRE (Chainlink Runtime Environment) workflow automatically fetches the USDT to ILS exchange rate and updates the PriceFeedReceiver contract on-chain.

## How It Works

The workflow:
1. **Fetches USDT/USD rate** from CoinGecko API (free, no API key needed)
2. **Fetches USD/ILS rate** from ExchangeRate-API (requires free API key)
3. **Calculates USDT/ILS rate** by multiplying the two rates
4. **Converts to 8 decimals** (Chainlink standard)
5. **Updates the PriceFeedReceiver contract** on-chain via Chainlink CRE

## 📁 Project Structure

```

stable_coin/
      ├── main.ts                    # Workflow implementation
      ├── workflow.yaml              # CRE workflow configuration
      ├── config.staging.json        # Staging configuration
      ├── config.production.json     # Production configuration
      ├── config.example.yaml        # Configuration template
      └── USDT_ILS_WORKFLOW.md       # Detailed workflow documentation
├── project.yml
├── secret.yml
└── README.md  #this file
```

## 🚀 Quick Start

### 1. Install Dependencies

```bash
cd stable_coin
bun install
```



**Get your free API key**: https://www.exchangerate-api.com/

### 3. Simulate Locally

```bash
# From project root
cre workflow simulate ./stable_coin -T staging-settings
```

### 4. Deploy to CRE

```bash
# Staging
cre workflow deploy ./stable_coin -T staging-settings

# Production
cre workflow deploy ./stable_coin -T production-settings
```
## Schedule

The workflow runs **every 1 minute** by default (configurable via cron schedule).

## Configuration

### 1. Get API Key

Get a free API key from ExchangeRate-API:
- Visit: https://www.exchangerate-api.com/
- Sign up for free account
- Copy your API key

### 2. Configure Workflow

Create or update your `config.json`:

```json
{
  "schedule": "*/1 * * * *",
  "priceFeedReceiverAddress": "0x...",
  "chainSelectorName": "ethereum-testnet-sepolia",
  "gasLimit": "500000"
}
```

**Parameters:**
- `schedule`: Cron expression for update frequency
- `priceFeedReceiverAddress`: Deployed PriceFeedReceiver contract address
- `chainSelectorName`: Network identifier (see chain-selectors.yml)
- `gasLimit`: Gas limit for transactions

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Chainlink CRE Workflow (runs every 1 minute)                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Fetch USDT/USD from CoinGecko                          │
│     ↓                                                       │
│     Example: 1 USDT = 1.0002 USD                           │
│                                                             │
│  2. Fetch USD/ILS from ExchangeRate-API                    │
│     ↓                                                       │
│     Example: 1 USD = 3.65 ILS                              │
│                                                             │
│  3. Calculate USDT/ILS                                     │
│     ↓                                                       │
│     1.0002 × 3.65 = 3.65073 ILS                            │
│                                                             │
│  4. Convert to 8 decimals                                  │
│     ↓                                                       │
│     3.65073 → 365073000 (uint224)                          │
│                                                             │
│  5. Encode report: (uint224 price, uint32 timestamp)      │
│     ↓                                                       │
│     abi.encode(365073000, 1234567890)                      │
│                                                             │
│  6. Submit to PriceFeedReceiver via CRE                    │
│     ↓                                                       │
│     priceFeedReceiver.onReport(metadata, report)           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ PriceFeedReceiver Contract (on-chain)                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Validates sender (Keystone Forwarder)                  │
│  2. Validates workflow ID                                  │
│  3. Validates author                                       │
│  4. Validates workflow name                                │
│  5. Decodes report: (uint224 price, uint32 timestamp)     │
│  6. Stores: latestPrice = 365073000                       │
│  7. Stores: latestTimestamp = 1234567890                  │
│  8. Emits: PriceUpdated(365073000, 1234567890)            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ On-Chain Rate Flow                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. LocalCurrencyToken (StableCoin) calls Converter        │
│     - mint/redeem use `converter.getExchangeRate(...)`    │
│  2. Converter queries PriceFeedReceiver (oracle mode)      │
│     - or uses its manual rate fallback                     │
│  3. Converter returns a 6-decimal rate to StableCoin       │
│  4. StableCoin uses that rate for mint/redeem math         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Price Format

- **USDT/USD**: Standard float (e.g., 1.0002)
- **USD/ILS**: Standard float (e.g., 3.65)
- **USDT/ILS (calculated)**: Standard float (e.g., 3.65073)
- **USDT/ILS (8 decimals)**: Integer (e.g., 365073000)
- **USDT/ILS (6 decimals in StableCoin)**: Integer (e.g., 3650730)

## Example Calculation

If rate is 3.65073 ILS per USDT:

1. **In PriceFeedReceiver**: Stored as `365073000` (uint224 with 8 decimals)
2. **In StableCoin**: Converted to `3650730` (6 decimals for internal use)
3. **User deposits**: 1000 USDT
4. **User receives**: 1000 × 3.650730 = 3650.73 ILS tokens

## API Rate Limits

### CoinGecko (USDT/USD)
- **Free tier**: 10-30 calls/minute
- **Cost**: Free
- **No API key needed**

### ExchangeRate-API (USD/ILS)
- **Free tier**: 1,500 requests/month (≈50/day)
- **Cost**: Free
- **Requires API key**

At 1-minute intervals:
- Daily calls: 1,440
- Monthly calls: ~43,200

**⚠️ WARNING**: Default schedule (every 1 minute) exceeds ExchangeRate-API free tier!

### Recommended Update Frequencies

| Frequency | Daily Updates | Monthly Gas Cost (ETH) | Use Case |
|-----------|--------------|------------------------|----------|
| 1 minute | 1,440 | ~52 | High-frequency trading |
| 5 minutes | 288 | ~10 | Active markets |
| 15 minutes | 96 | ~3.5 | Standard DeFi |
| 30 minutes | 48 | ~1.7 | Stable assets |
| 1 hour | 24 | ~0.9 | Low volatility |

## Simulation and Testing

### 1. Local Simulation

```bash
# From project root
cre workflow simulate ./workflow01
```

Select trigger type:
1. **Cron trigger**: Tests scheduled price updates
2. **Log trigger**: Tests manual price updates

### 2. Monitor Logs

Check workflow execution logs:
- Price fetching status
- API responses
- Calculated rates
- Transaction hashes
- Error messages

