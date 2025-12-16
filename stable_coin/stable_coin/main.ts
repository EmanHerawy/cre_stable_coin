import {
	bytesToHex,
	ConsensusAggregationByFields,
	type CronPayload,
	cre,
	getNetwork,
	type HTTPSendRequester,
	hexToBase64,
	median,
	Runner,
	type Runtime,
	TxStatus,
} from '@chainlink/cre-sdk'
import { encodeAbiParameters } from 'viem'
import { z } from 'zod'

const configSchema = z.object({
	schedule: z.string(), // Cron schedule (e.g., "*/1 * * * *" for every 1 minute)
	priceFeedReceiverAddress: z.string(), // PriceFeedReceiver contract address
	chainSelectorName: z.string(), // Network chain selector name
	gasLimit: z.string(), // Gas limit for transactions
})

type Config = z.infer<typeof configSchema>

// Interfaces for API responses
interface ExchangeRateResponse {
	result: string
	documentation: string
	terms_of_use: string
	time_last_update_unix: number
	time_last_update_utc: string
	time_next_update_unix: number
	time_next_update_utc: string
	base_code: string
	target_code: string
	conversion_rate: number
}

interface CoinGeckoResponse {
	tether: {
		usd: number
	}
}

interface UsdtToIlsResult {
	rate: number // USDT to ILS rate with 6 decimals
	usdtToUsd: number
	usdToIls: number
	timestamp: number
}

// Utility function to safely stringify objects with bigints
const safeJsonStringify = (obj: any): string =>
	JSON.stringify(obj, (_, value) => (typeof value === 'bigint' ? value.toString() : value), 2)

/**
 * Fetches the current USD to ILS exchange rate
 */
const fetchUsdToIlsRate = (
	sendRequester: HTTPSendRequester,
	apiKey: string,
): { rate: number } => {
	const url = `https://v6.exchangerate-api.com/v6/${apiKey}/pair/USD/ILS`

  // 1. Construct the GET request with cacheSettings
      const req = {
        url: url,
        method: "GET" as const,
        headers: {
          "Content-Type": "application/json",
        },
        cacheSettings: {
          readFromCache: true, // Enable reading from cache
          maxAgeMs: 60000, // Accept cached responses up to 60 seconds old
        },
      };
	const response = sendRequester.sendRequest(req).result();

	if (response.statusCode !== 200) {
		throw new Error(`USD/ILS API request failed with status: ${response.statusCode}`)
	}

	const responseText = Buffer.from(response.body).toString('utf-8')

	const data: ExchangeRateResponse = JSON.parse(responseText)

	if (data.result !== 'success') {
		throw new Error(`USD/ILS API returned error: ${data.result}`)
	}

	return {
		rate: data.conversion_rate,
	}
}

/**
 * Fetches the current USDT to USD rate from CoinGecko
 */
const fetchUsdtToUsdRate = (sendRequester: HTTPSendRequester): { rate: number } => {

	const url = 'https://api.coingecko.com/api/v3/simple/price?ids=tether&vs_currencies=usd'
  // 1. Construct the GET request with cacheSettings
      const req = {
        url: url,
        method: "GET" as const,
        headers: {
          "Content-Type": "application/json",
        },
        cacheSettings: {
          readFromCache: true, // Enable reading from cache
          maxAgeMs: 60000, // Accept cached responses up to 60 seconds old
        },
      };
	const response = sendRequester.sendRequest(req).result();

	if (response.statusCode !== 200) {
		throw new Error(`USDT/USD API request failed with status: ${response.statusCode}`)
	}

	const bodyArray = Object.values(response.body)
	const responseText = Buffer.from(bodyArray).toString('utf-8')
	const data: CoinGeckoResponse = JSON.parse(responseText)

	if (!data.tether || !data.tether.usd) {
		throw new Error('Invalid response from CoinGecko')
	}

	return { rate: data.tether.usd }
}



/**
 * Updates the price feed receiver contract with new USDT/ILS price
 */
const updatePriceFeed = (runtime: Runtime<Config>, priceData: UsdtToIlsResult): string => {
	const evmConfig = runtime.config
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: evmConfig.chainSelectorName,
		isTestnet: true,
	})

	if (!network) {
		throw new Error(`Network not found for chain selector name: ${evmConfig.chainSelectorName}`)
	}

	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	runtime.log(`Updating price feed with rate: ${priceData.rate} (${priceData.rate / 1e8} ILS per USDT)`)
	runtime.log(`USDT/USD: ${priceData.usdtToUsd}, USD/ILS: ${priceData.usdToIls}`)
	runtime.log(`Timestamp: ${priceData.timestamp}`)

	// Encode the report data: (uint224 price, uint32 timestamp)
	// The price is stored as uint224 with 6 decimals
	const price = BigInt(Math.floor(priceData.rate))
	const timestamp = BigInt(Math.floor(priceData.timestamp))

	const reportData = encodeAbiParameters(
		[
			{ type: 'uint224' },
			{ type: 'uint32' }
		],
		[price, timestamp]
	)

	runtime.log(`Encoded report: ${reportData}`)

	// Generate report using consensus capability
	const reportResponse = runtime
		.report({
			encodedPayload: hexToBase64(reportData),
			encoderName: 'evm',
			signingAlgo: 'ecdsa',
			hashingAlgo: 'keccak256',
		})
		.result()

	// Write report to the PriceFeedReceiver contract
	const resp = evmClient
		.writeReport(runtime, {
			receiver: evmConfig.priceFeedReceiverAddress,
			report: reportResponse,
			gasConfig: {
				gasLimit: evmConfig.gasLimit,
			},
		})
		.result()

	const txStatus = resp.txStatus

	if (txStatus !== TxStatus.SUCCESS) {
		throw new Error(`Failed to write price report: ${resp.errorMessage || txStatus}`)
	}

	const txHash = resp.txHash || new Uint8Array(32)

	runtime.log(`Price update transaction succeeded at txHash: ${bytesToHex(txHash)}`)

	return bytesToHex(txHash)
}

/**
 * Main workflow logic to fetch and update USDT/ILS price
 */
const updateUsdtIlsPrice = (runtime: Runtime<Config>): string => {
	runtime.log('Fetching USDT/ILS exchange rate...')

	const httpCapability = new cre.capabilities.HTTPClient()

	// ▶ Each HTTP request MUST have its own aggregation
	// Fetch USDT to USD rate with consensus aggregation
	const usdtToUsdData = httpCapability
		.sendRequest(
			runtime,
			fetchUsdtToUsdRate,
			ConsensusAggregationByFields<{ rate: number }>({
				rate: median,
			}),
		)()
		.result()

	runtime.log(`USDT/USD rate: ${usdtToUsdData.rate}`)
 let exchangeRateApiKey: string | undefined;
      
              try {
      
          const secret = runtime.getSecret({ id:'API_KEY'}).result();
          console.log("secret",secret);
          exchangeRateApiKey = secret.value || '';
		  console.log("exchangeRateApiKey",exchangeRateApiKey);
		  
        } catch (secretError) {
          runtime.log(`Warning: Could not read API_KEY from secrets: ${secretError instanceof Error ? secretError.message : String(secretError)}`);
        }
	// Fetch USD to ILS rate with consensus aggregation
	const usdToIlsData = httpCapability
		.sendRequest(
			runtime,
			(sendRequester: HTTPSendRequester, apiKey: string) => fetchUsdToIlsRate(sendRequester, apiKey),
			ConsensusAggregationByFields<{ rate: number }>({
				rate: median,
			}),
		)(exchangeRateApiKey)
		.result()

	runtime.log(`USD/ILS rate: ${usdToIlsData.rate}`)

	// ▶ FINAL math does NOT require aggregation
	// Now combine the aggregated results with math
	const usdtToIlsRate = usdtToUsdData.rate * usdToIlsData.rate

	// Convert to 6 decimals (Chainlink standard)
	const rateWith6Decimals = Math.round(usdtToIlsRate * 1e6)

	const priceData: UsdtToIlsResult = {
		rate: rateWith6Decimals,
		usdtToUsd: usdtToUsdData.rate,
		usdToIls: usdToIlsData.rate,
		timestamp: Math.floor(runtime.now() as any / 1000),
	}

	runtime.log(`Price data calculated: ${safeJsonStringify(priceData)}`)

	// Update the price feed receiver contract
	const txHash = updatePriceFeed(runtime, priceData)

	return txHash
}

/**
 * Cron trigger handler - runs every 1 minute
 */
const onCronTrigger = (runtime: Runtime<Config>, payload: CronPayload): string => {
	if (!payload.scheduledExecutionTime) {
		throw new Error('Scheduled execution time is required')
	}

	runtime.log(`Running scheduled price update at ${payload.scheduledExecutionTime}`)

	return updateUsdtIlsPrice(runtime)
}

/**
 * Initialize workflow with triggers
 */
const initWorkflow = (config: Config) => {
	const cronTrigger = new cre.capabilities.CronCapability()

	return [
		// Cron trigger: runs every 1 minute (or as specified in schedule)
		cre.handler(
			cronTrigger.trigger({
				schedule: config.schedule,
			}),
			onCronTrigger,
		),
	]
}

export async function main() {
	const runner = await Runner.newRunner<Config>({
		configSchema,
	})
	await runner.run(initWorkflow)
}

main()
