// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceFeedReceiver.sol";
import "../src/StableCoin.sol";
import "../src/MockUSDT.sol";
import "./USDTAddressProvider.sol";

/**
 * @title Deploy Script for StableCoin System
 * @notice Deploys PriceFeedReceiver and LocalCurrencyToken contracts
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployScript is Script {
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
    }

    function run() external {
        // Load configuration from environment or use defaults
        DeployConfig memory config = getConfig();

        // Validate configuration
        require(config.admin != address(0), "Admin address not set");
        require(config.initialRate > 0, "Initial rate must be greater than 0");

        console.log("=== StableCoin Deployment ===");
        console.log("Network:", USDTAddressProvider.getCurrentNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("Admin Address:", config.admin);
        console.log("Initial Rate:", config.initialRate);
        console.log("Currency:", config.currencyName);
        console.log("");

        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Determine USDT address or deploy mock
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

        // Step 1: Deploy PriceFeedReceiver
        // Deploy with deployer as initial owner, then transfer to admin after configuration
        console.log("Deploying PriceFeedReceiver...");
        PriceFeedReceiver priceFeedReceiver = new PriceFeedReceiver(deployer);
        console.log("PriceFeedReceiver deployed at:", address(priceFeedReceiver));

        // Step 2: Configure PriceFeedReceiver
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

        // Transfer PriceFeedReceiver ownership to admin if different from deployer
        if (config.admin != deployer) {
            console.log("Transferring PriceFeedReceiver ownership to:", config.admin);
            priceFeedReceiver.transferOwnership(config.admin);
        }

        // Step 3: Deploy StableCoin
        console.log("");
        console.log("Deploying LocalCurrencyToken...");
        LocalCurrencyToken stableCoin = new LocalCurrencyToken(
            usdtAddress,
            config.currencyName,
            config.currencySymbol,
            config.initialRate,
            config.admin,
            address(priceFeedReceiver)
        );
        console.log("LocalCurrencyToken deployed at:", address(stableCoin));

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("PriceFeedReceiver:", address(priceFeedReceiver));
        console.log("LocalCurrencyToken:", address(stableCoin));
        console.log("Token Name:", stableCoin.name());
        console.log("Token Symbol:", stableCoin.symbol());
        console.log("Initial Rate:", stableCoin.manualRate());
        console.log("Using Oracle:", stableCoin.useOracle());
        console.log("Min Deposit:", stableCoin.minDeposit());
        console.log("Min Withdrawal:", stableCoin.minWithdrawal());
        console.log("Max Price Age:", stableCoin.maxPriceAge());
        console.log("");
        console.log("Deployment complete!");
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

        // If environment variables not set, use default values
        if (admin == address(0)) {
            console.log("WARNING: Using default configuration for testing");
            console.log("Set environment variables for production deployment");
            console.log("");

            admin = msg.sender;
            currencyName = "Egyptian Pound Digital";
            currencySymbol = "EGPd";
            initialRate = 50e6; // 50 EGP per USDT
            workflowName = bytes10("USD_EGP");
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
            initialRate: initialRate
        });
    }

    /**
     * @notice Helper function to verify deployment
     * @dev Can be called after deployment to verify contract state
     */
    function verify(address priceFeedReceiverAddr, address stableCoinAddr) external view {
        console.log("=== Verifying Deployment ===");

        PriceFeedReceiver receiver = PriceFeedReceiver(priceFeedReceiverAddr);
        LocalCurrencyToken token = LocalCurrencyToken(stableCoinAddr);

        console.log("PriceFeedReceiver Configuration:");
        console.log("  Forwarders:", receiver.getKeystoneForwarderCount());
        console.log("  Workflow IDs:", receiver.getExpectedWorkflowIdCount());
        console.log("  Authors:", receiver.getExpectedAuthorCount());
        console.log("  Workflow Names:", receiver.getExpectedWorkflowNameCount());
        console.log("");

        console.log("LocalCurrencyToken Configuration:");
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
        console.log("  USDT Address:", address(token.usdt()));
        console.log("  PriceFeed Address:", address(token.priceFeedReceiver()));
        console.log("  Manual Rate:", token.manualRate());
        console.log("  Use Oracle:", token.useOracle());
        console.log("  Min Deposit:", token.minDeposit());
        console.log("  Min Withdrawal:", token.minWithdrawal());
        console.log("  Max Price Age:", token.maxPriceAge());
        console.log("  Paused:", token.paused());
        console.log("  Total Supply:", token.totalSupply());
        console.log("  Total Collateral:", token.getTotalCollateral());
    }
}
