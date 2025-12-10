// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceFeedReceiver.sol";
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

        // Deploy StableCoin
        console.log("4. Deploying LocalCurrencyToken (EGPd)...");
        LocalCurrencyToken stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Egyptian Pound Digital",
            "EGPd",
            50e6, // 50 EGP per USDT
            deployer,
            address(priceFeedReceiver)
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

        console.log("LocalCurrencyToken:");
        console.log("  Name:", stableCoin.name());
        console.log("  Symbol:", stableCoin.symbol());
        console.log("  USDT:", address(stableCoin.usdt()));
        console.log("  PriceFeed:", address(stableCoin.priceFeedReceiver()));
        console.log("  Manual Rate:", stableCoin.manualRate());
        console.log("  Use Oracle:", stableCoin.useOracle());
        console.log("  Min Deposit:", stableCoin.minDeposit());
        console.log("  Min Withdrawal:", stableCoin.minWithdrawal());
        console.log("  Max Price Age:", stableCoin.maxPriceAge());
        console.log("  Paused:", stableCoin.paused());
        console.log("  Total Supply:", stableCoin.totalSupply());
        console.log("  Total Collateral:", stableCoin.getTotalCollateral());
        console.log("");

        // Test basic functionality
        console.log("=== Testing Basic Functionality ===");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Test mint
        console.log("5. Testing mint function...");

        usdt.approve(address(stableCoin), 1000e6);
        console.log("   Approved USDT");

        // Switch to manual rate for testing
        stableCoin.pause();
        stableCoin.toggleUseOracle();
        stableCoin.unpause();
        console.log("   Switched to manual rate");

        uint256 minted = stableCoin.mint(1000e6);
        console.log("   Minted:", minted / 1e18);
        console.log("   Collateral:", stableCoin.getTotalCollateral() / 1e6);
        console.log("");

        // Test redeem
        console.log("6. Testing redeem function...");
        uint256 redeemed = stableCoin.redeem(minted / 2);
        console.log("   Redeemed:", minted / 2 / 1e18);
        console.log("   Received USDT:", redeemed / 1e6);
        console.log("");

        vm.stopBroadcast();

        console.log("=== Deployment Summary ===");
        console.log("Mock USDT:", address(usdt));
        console.log("PriceFeedReceiver:", address(priceFeedReceiver));
        console.log("LocalCurrencyToken:", address(stableCoin));
        console.log("");
        console.log("Test deployment successful!");
    }
}
