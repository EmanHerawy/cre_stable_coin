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
	rate: number // USDT to ILS rate as integer with 6 decimals (e.g., 3.65073 ILS = 3650730)
	usdtToUsd: number
	usdToIls: number
}

interface PriceDataWithTimestamp extends UsdtToIlsResult {
	timestamp: number
}
// a function that fetches the current USDT to ILS rate
const getRate = (sendRequester: HTTPSendRequester, exchangeRateApiKey: string): UsdtToIlsResult => {
		const fetchUsdtToUsdUrl= 'https://api.coingecko.com/api/v3/simple/price?ids=tether&vs_currencies=usd'
		const fetchUsdToIlsUrl= `https://v6.exchangerate-api.com/v6/${exchangeRateApiKey}/pair/USD/ILS`

	// 1. Construct the GET request with cacheSettings
      const reqUsdToIls = {
        url: fetchUsdToIlsUrl,
        method: "GET" as const,
        headers: {
          "Content-Type": "application/json",
        },
        cacheSettings: {
          readFromCache: true, // Enable reading from cache
          maxAgeMs: 60000, // Accept cached responses up to 60 seconds old
        },
      };
	      const reqUsdtToUsd = {
        url: fetchUsdtToUsdUrl,
        method: "GET" as const,
        headers: {
          "Content-Type": "application/json",
        },
        cacheSettings: {
          readFromCache: true, // Enable reading from cache
          maxAgeMs: 60000, // Accept cached responses up to 60 seconds old
        },
      };
	const responseUsdToIls = sendRequester.sendRequest(reqUsdToIls).result()
	const responseUsdtToUsd = sendRequester.sendRequest(reqUsdtToUsd).result()



	if (responseUsdToIls.statusCode !== 200) {
		throw new Error(`USD/ILS API request failed with status: ${responseUsdToIls.statusCode}`)
	}
	if (responseUsdtToUsd.statusCode !== 200) {
		throw new Error(`USDT/USD API request failed with status: ${responseUsdtToUsd.statusCode}`)
	}


	// parse the response body as a JSON object
	// for USD/ILS
	const responseUsdToIlsText = Buffer.from(responseUsdToIls.body).toString('utf-8')

	const dataUsdToIls: ExchangeRateResponse = JSON.parse(responseUsdToIlsText)

	if (dataUsdToIls.result !== 'success') {
		throw new Error(`USD/ILS API returned error: ${dataUsdToIls.result}`)
	}
	const bodyArray = Object.values(responseUsdtToUsd.body)
	const responseeUsdtToUsdText = Buffer.from(bodyArray).toString('utf-8')
	const dataeUsdtToUsd: CoinGeckoResponse = JSON.parse(responseeUsdtToUsdText)

	if (!dataeUsdtToUsd.tether || !dataeUsdtToUsd.tether.usd) {
		throw new Error('Invalid response from CoinGecko')
	}

	const usdtToUsd = dataeUsdtToUsd.tether.usd
	const usdToIls = dataUsdToIls.conversion_rate

	return {
		rate: Math.floor(usdtToUsd * usdToIls * 1e6),
		usdtToUsd: usdtToUsd,
		usdToIls: usdToIls,
	}
}
// Utility function to safely stringify objects with bigints
const safeJsonStringify = (obj: any): string =>
	JSON.stringify(obj, (_, value) => (typeof value === 'bigint' ? value.toString() : value), 2)


/**
 * Updates the price feed receiver contract with new USDT/ILS price
 */
const updatePriceFeed = (runtime: Runtime<Config>, priceData: PriceDataWithTimestamp): string => {
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

	// Get API key from secrets
	let exchangeRateApiKey: string | undefined;
	try {
		const secret = runtime.getSecret({ id:'API_KEY'}).result();
		exchangeRateApiKey = secret.value || '';
	} catch (secretError) {
		runtime.log(`Warning: Could not read API_KEY from secrets: ${secretError instanceof Error ? secretError.message : String(secretError)}`);
		exchangeRateApiKey = '';
	}

	const httpCapability = new cre.capabilities.HTTPClient()

	// ▶ Each HTTP request MUST have its own aggregation
	// Fetch USDT to ILS rate with consensus aggregation
	const rateData = httpCapability
		.sendRequest(
			runtime,
			(sendRequester: HTTPSendRequester, apiKey: string) => getRate(sendRequester, apiKey),
			ConsensusAggregationByFields<{ rate: number , usdtToUsd: number, usdToIls: number}>({
				rate: median,
				usdtToUsd: median,
				usdToIls: median,
			}),
		)(exchangeRateApiKey)
		.result()

	// Add timestamp using runtime.now() as recommended
	const priceData: PriceDataWithTimestamp = {
		...rateData,
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
