// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceFeedReceiver.sol";
import "../src/Converter.sol";
import "../src/StableCoin.sol";
import "../test/StableCoin.t.sol"; // Import MockUSDT

/**
 * @title Test Deployment Script
 * @notice Deploys complete system including mock USDT for testing
 */
contract DeployTestScript is Script {
    function run() external {
        console.log("=== Test Deployment (with Mock USDT) ===");
        console.log("");

        // Get private key from environment variable
        // Falls back to Anvil's first account if not set
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock USDT
        console.log("1. Deploying Mock USDT...");
        MockUSDT usdt = new MockUSDT();
        console.log("   Mock USDT deployed at:", address(usdt));
        console.log("   USDT Balance:", usdt.balanceOf(deployer));
        console.log("");

        // Deploy PriceFeedReceiver
        console.log("2. Deploying PriceFeedReceiver...");
        PriceFeedReceiver priceFeedReceiver = new PriceFeedReceiver(deployer);
        console.log("   PriceFeedReceiver deployed at:", address(priceFeedReceiver));
        console.log("");

        // Configure PriceFeedReceiver
        console.log("3. Configuring PriceFeedReceiver...");
        address forwarder = address(0x1234567890123456789012345678901234567890);
        address author = address(0x2345678901234567890123456789012345678901);
        bytes32 workflowId = keccak256("test-workflow");
        bytes10 workflowName = bytes10("USD_EGP");

        priceFeedReceiver.addKeystoneForwarder(forwarder);
        console.log("   Added forwarder:", forwarder);

        priceFeedReceiver.addExpectedWorkflowId(workflowId);
        console.log("   Added workflow ID:", vm.toString(workflowId));

        priceFeedReceiver.addExpectedAuthor(author);
        console.log("   Added author:", author);

        priceFeedReceiver.addExpectedWorkflowName(workflowName);
        console.log("   Added workflow name:", vm.toString(abi.encodePacked(workflowName)));
        console.log("");

        // Deploy Converter
        console.log("4. Deploying Converter...");
        Converter converter = new Converter(
            50e6, // 50 EGP per USDT
            2000, // 20% max deviation
            5000, // 50% hard cap
            3600, // 1 hour max price age
            deployer,
            address(priceFeedReceiver)
        );
        console.log("   Converter deployed at:", address(converter));
        console.log("");

        // Deploy StableCoin
        console.log("5. Deploying LocalCurrencyToken (EGPd)...");
        LocalCurrencyToken stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Egyptian Pound Digital",
            "EGPd",
            address(converter),
            deployer
        );
        console.log("   LocalCurrencyToken deployed at:", address(stableCoin));
        console.log("");

        vm.stopBroadcast();

        // Verify deployment
        console.log("=== Deployment Verification ===");
        console.log("");

        console.log("PriceFeedReceiver:");
        console.log("  Owner:", priceFeedReceiver.owner());
        console.log("  Forwarders count:", priceFeedReceiver.getKeystoneForwarderCount());
        console.log("  Workflow IDs count:", priceFeedReceiver.getExpectedWorkflowIdCount());
        console.log("  Authors count:", priceFeedReceiver.getExpectedAuthorCount());
        console.log("  Workflow names count:", priceFeedReceiver.getExpectedWorkflowNameCount());
        console.log("");

        console.log("Converter:");
        (uint256 manualRate, , ) = converter.getManualPriceInfo();
        console.log("  Manual Rate:", manualRate);
        console.log("  Use Oracle:", converter.useOracle());
        console.log("  Max Price Age:", converter.maxPriceAge());
        console.log("  Max Deviation:", converter.maxPriceDeviationBps(), "bps");
        console.log("");

        console.log("LocalCurrencyToken:");
        console.log("  Name:", stableCoin.name());
        console.log("  Symbol:", stableCoin.symbol());
        console.log("  USDT:", address(stableCoin.usdt()));
        console.log("  Converter:", address(stableCoin.converter()));
        console.log("  Min Deposit:", stableCoin.minDeposit());
        console.log("  Min Withdrawal:", stableCoin.minWithdrawal());
        console.log("  Paused:", stableCoin.paused());
        console.log("");

        console.log("=== Deployment Complete! ===");
        console.log("");
        console.log("Next steps:");
        console.log("1. Mint some USDT to a test account");
        console.log("2. Approve USDT spending");
        console.log("3. Mint stablecoins");
        console.log("4. Test redemption");
    }
}
