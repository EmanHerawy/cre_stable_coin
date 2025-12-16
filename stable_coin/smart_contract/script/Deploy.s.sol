// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceFeedReceiver.sol";
import "../src/Converter.sol";
import "../src/StableCoin.sol";
import "../src/MockUSDT.sol";
import "./USDTAddressProvider.sol";

/**
 * @title DeployRefactoredScript for Refactored StableCoin System
 * @notice Deploys PriceFeedReceiver, Converter, and LocalCurrencyToken contracts
 * @dev Run with: forge script script/DeployRefactored.s.sol --rpc-url <RPC_URL> --broadcast --verify
 *
 * Architecture:
 * - PriceFeedReceiver: Receives oracle price updates from Chainlink CRE
 * - Converter: Manages exchange rates (oracle + manual fallback)
 * - LocalCurrencyToken: Main stablecoin contract (minting/redeeming)
 */
contract DeployRefactoredScript is Script {
    // Configuration parameters
    struct DeployConfig {
        address usdtAddress;
        address admin;
        address forwarder;
        address author;
        bytes32 workflowId;
        bytes10 workflowName;
        string currencyName;
        string currencySymbol;
        uint256 initialRate;
        uint256 maxPriceDeviationBps;
        uint256 maxDeviationLimit;
        uint256 maxPriceAge;
        bool useOracle;
    }

    function run() external {
        // Load configuration from environment or use defaults
        DeployConfig memory config = getConfig();

        // Validate configuration
        if (config.admin == address(0)) revert("Admin address not set");
        if (config.initialRate == 0) revert("Initial rate must be greater than 0");
        if (config.maxPriceDeviationBps == 0) revert("Max price deviation must be greater than 0");
        if (config.maxDeviationLimit == 0) revert("Max deviation limit must be greater than 0");
        if (config.maxPriceAge == 0) revert("Max price age must be greater than 0");

        console.log("=== StableCoin Refactored Deployment ===");
        console.log("Network:", USDTAddressProvider.getCurrentNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("Admin Address:", config.admin);
        console.log("Initial Rate:", config.initialRate);
        console.log("Currency:", config.currencyName);
        console.log("Use Oracle:", config.useOracle);
        console.log("");

        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // ============ STEP 1: Deploy or get USDT ============
        address usdtAddress = config.usdtAddress;
        if (usdtAddress == address(0)) {
            // Try to get USDT from provider
            usdtAddress = USDTAddressProvider.getUSDTAddress();

            if (usdtAddress == address(0)) {
                // USDT not deployed on this network, deploy mock
                console.log("USDT not found on this network, deploying MockUSDT...");
                MockUSDT mockUSDT = new MockUSDT();
                usdtAddress = address(mockUSDT);
                console.log("MockUSDT deployed at:", usdtAddress);
            } else {
                console.log("Using existing USDT at:", usdtAddress);
            }
        } else {
            console.log("Using configured USDT at:", usdtAddress);
        }

        console.log("");

        // ============ STEP 2: Deploy PriceFeedReceiver ============
        address priceFeedReceiverAddr = address(0);

        if (config.useOracle) {
            console.log("Deploying PriceFeedReceiver...");
            PriceFeedReceiver priceFeedReceiver = new PriceFeedReceiver(deployer);
            priceFeedReceiverAddr = address(priceFeedReceiver);
            console.log("PriceFeedReceiver deployed at:", priceFeedReceiverAddr);

            // Configure PriceFeedReceiver
            if (config.forwarder != address(0)) {
                console.log("Adding Keystone Forwarder:", config.forwarder);
                priceFeedReceiver.addKeystoneForwarder(config.forwarder);
            }

            if (config.workflowId != bytes32(0)) {
                console.log("Adding Workflow ID:", vm.toString(config.workflowId));
                priceFeedReceiver.addExpectedWorkflowId(config.workflowId);
            }

            if (config.author != address(0)) {
                console.log("Adding Expected Author:", config.author);
                priceFeedReceiver.addExpectedAuthor(config.author);
            }

            if (config.workflowName != bytes10(0)) {
                console.log("Adding Workflow Name:", vm.toString(abi.encodePacked(config.workflowName)));
                priceFeedReceiver.addExpectedWorkflowName(config.workflowName);
            }

            // Transfer ownership to admin if different from deployer
            if (config.admin != deployer) {
                console.log("Transferring PriceFeedReceiver ownership to:", config.admin);
                priceFeedReceiver.transferOwnership(config.admin);
            }
        } else {
            console.log("Oracle disabled, skipping PriceFeedReceiver deployment");
        }

        console.log("");

        // ============ STEP 3: Deploy Converter ============
        console.log("Deploying Converter...");
        Converter converter = new Converter(
            config.initialRate,
            config.maxPriceDeviationBps,
            config.maxDeviationLimit,
            config.maxPriceAge,
            config.admin,
            priceFeedReceiverAddr
        );
        console.log("Converter deployed at:", address(converter));
        console.log("  Initial Rate:", config.initialRate);
        console.log("  Max Deviation:", config.maxPriceDeviationBps, "bps");
        console.log("  Max Deviation Limit:", config.maxDeviationLimit, "bps");
        console.log("  Max Price Age:", config.maxPriceAge, "seconds");
        console.log("  Use Oracle:", converter.useOracle());

        console.log("");

        // ============ STEP 4: Deploy LocalCurrencyToken ============
        console.log("Deploying LocalCurrencyToken...");
        LocalCurrencyToken stableCoin = new LocalCurrencyToken(
            usdtAddress,
            config.currencyName,
            config.currencySymbol,
            address(converter),
            config.admin
        );
        console.log("LocalCurrencyToken deployed at:", address(stableCoin));

        vm.stopBroadcast();

        // ============ Print deployment summary ============
        console.log("");
        console.log("=== Deployment Summary ===");
        if (priceFeedReceiverAddr != address(0)) {
            console.log("PriceFeedReceiver:", priceFeedReceiverAddr);
        }
        console.log("Converter:", address(converter));
        console.log("LocalCurrencyToken:", address(stableCoin));
        console.log("");
        console.log("Token Configuration:");
        console.log("  Name:", stableCoin.name());
        console.log("  Symbol:", stableCoin.symbol());
        console.log("  USDT Address:", address(stableCoin.usdt()));
        console.log("  Converter Address:", address(stableCoin.converter()));
        console.log("  Min Deposit:", stableCoin.minDeposit());
        console.log("  Min Withdrawal:", stableCoin.minWithdrawal());
        console.log("");
        console.log("Converter Configuration:");
        (uint256 manualRate, , ) = converter.getManualPriceInfo();
        console.log("  Manual Rate:", manualRate);
        console.log("  Using Oracle:", converter.useOracle());
        console.log("  Max Price Age:", converter.maxPriceAge());
        console.log("  Max Deviation:", converter.maxPriceDeviationBps(), "bps");
        console.log("");
        console.log("Deployment complete!");
        console.log("");
        console.log("Save these addresses for future reference:");
        console.log("export PRICE_FEED_RECEIVER=", priceFeedReceiverAddr);
        console.log("export CONVERTER=", address(converter));
        console.log("export STABLE_COIN=", address(stableCoin));
    }

    function getConfig() internal view returns (DeployConfig memory) {
        // Try to load from environment variables
        address usdtAddress = vm.envOr("USDT_ADDRESS", address(0));
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));
        address forwarder = vm.envOr("FORWARDER_ADDRESS", address(0));
        address author = vm.envOr("AUTHOR_ADDRESS", address(0));

        bytes32 workflowId = vm.envOr("WORKFLOW_ID", bytes32(0));
        string memory workflowNameStr = vm.envOr("WORKFLOW_NAME", string(""));
        bytes10 workflowName = bytes10(0);
        if (bytes(workflowNameStr).length > 0) {
            workflowName = bytes10(bytes(workflowNameStr));
        }

        string memory currencyName = vm.envOr("CURRENCY_NAME", string(""));
        string memory currencySymbol = vm.envOr("CURRENCY_SYMBOL", string(""));
        uint256 initialRate = vm.envOr("INITIAL_RATE", uint256(0));
        uint256 maxPriceDeviationBps = vm.envOr("MAX_PRICE_DEVIATION_BPS", uint256(0));
        uint256 maxDeviationLimit = vm.envOr("MAX_DEVIATION_LIMIT", uint256(0));
        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(0));
        bool useOracle = vm.envOr("USE_ORACLE", false);

        // If environment variables not set, use default values
        if (admin == address(0)) {
            console.log("WARNING: Using default configuration for testing");
            console.log("Set environment variables for production deployment");
            console.log("");

            admin = msg.sender;
            currencyName = "Egyptian Pound Digital";
            currencySymbol = "EGPd";
            initialRate = 50e6; // 50 EGP per USDT
            maxPriceDeviationBps = 2000; // 20%
            maxDeviationLimit = 5000; // 50%
            maxPriceAge = 3600; // 1 hour
            workflowName = bytes10("USD_EGP");
            useOracle = false; // Default to manual mode for safety
        }

        return DeployConfig({
            usdtAddress: usdtAddress,
            admin: admin,
            forwarder: forwarder,
            author: author,
            workflowId: workflowId,
            workflowName: workflowName,
            currencyName: currencyName,
            currencySymbol: currencySymbol,
            initialRate: initialRate,
            maxPriceDeviationBps: maxPriceDeviationBps,
            maxDeviationLimit: maxDeviationLimit,
            maxPriceAge: maxPriceAge,
            useOracle: useOracle
        });
    }

    /**
     * @notice Helper function to verify deployment
     * @dev Can be called after deployment to verify contract state
     */
    function verify(
        address priceFeedReceiverAddr,
        address converterAddr,
        address stableCoinAddr
    ) external view {
        console.log("=== Verifying Deployment ===");

        if (priceFeedReceiverAddr != address(0)) {
            PriceFeedReceiver receiver = PriceFeedReceiver(priceFeedReceiverAddr);
            console.log("PriceFeedReceiver Configuration:");
            console.log("  Forwarders:", receiver.getKeystoneForwarderCount());
            console.log("  Workflow IDs:", receiver.getExpectedWorkflowIdCount());
            console.log("  Authors:", receiver.getExpectedAuthorCount());
            console.log("  Workflow Names:", receiver.getExpectedWorkflowNameCount());
            console.log("");
        }

        Converter converter = Converter(converterAddr);
        console.log("Converter Configuration:");
        (uint256 manualRate, uint256 manualTimestamp, ) = converter.getManualPriceInfo();
        (uint256 oracleRate, uint256 oracleTimestamp, ) = converter.getOraclePriceInfo();
        console.log("  Manual Rate:", manualRate);
        console.log("  Manual Timestamp:", manualTimestamp);
        console.log("  Oracle Rate:", oracleRate);
        console.log("  Oracle Timestamp:", oracleTimestamp);
        console.log("  Use Oracle:", converter.useOracle());
        console.log("  Max Price Age:", converter.maxPriceAge());
        console.log("  Max Deviation:", converter.maxPriceDeviationBps(), "bps");
        console.log("  Max Deviation Limit:", converter.MAX_DEVIATION_LIMIT(), "bps");
        console.log("  Price Stale:", converter.isPriceStale());
        console.log("");

        LocalCurrencyToken token = LocalCurrencyToken(stableCoinAddr);
        console.log("LocalCurrencyToken Configuration:");
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
        console.log("  Decimals:", token.decimals());
        console.log("  USDT Address:", address(token.usdt()));
        console.log("  Converter Address:", address(token.converter()));
        console.log("  Min Deposit:", token.minDeposit());
        console.log("  Min Withdrawal:", token.minWithdrawal());
        console.log("  Mint Fee:", token.mintFeeBps(), "bps");
        console.log("  Redeem Fee:", token.redeemFeeBps(), "bps");
        console.log("  Paused:", token.paused());
        console.log("  Total Supply:", token.totalSupply());
        console.log("  Total Collateral:", token.getTotalCollateral());
        console.log("  Net Collateral:", token.getNetCollateral());
        console.log("  Fees Collected:", token.totalFeesToBeCollected());
    }
}
