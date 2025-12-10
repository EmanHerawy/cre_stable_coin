// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
import "../script/USDTAddressProvider.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title ForkTest
 * @notice Tests StableCoin system using real USDT contracts on forked networks
 * @dev Run with: forge test --match-contract ForkTest --fork-url <RPC_URL>
 *
 * Example commands:
 * - Ethereum Mainnet: forge test --match-contract ForkTest --fork-url https://eth.llamarpc.com
 * - Polygon: forge test --match-contract ForkTest --fork-url https://polygon.llamarpc.com
 * - Arbitrum: forge test --match-contract ForkTest --fork-url https://arb1.arbitrum.io/rpc
 * - BSC: forge test --match-contract ForkTest --fork-url https://bsc-dataseed.binance.org
 */
contract ForkTest is Test {
    LocalCurrencyToken public stableCoin;
    IERC20 public usdt;

    address public admin;
    address public user1;
    address public user2;

    // Whale addresses with large USDT balances (network-specific)
    mapping(uint256 => address) public whaleAddresses;

    uint256 constant INITIAL_RATE = 3_223_000; // 3.223 ILS per USDT (6 decimals)

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Configure whale addresses for each network
        configureWhaleAddresses();

        // Get USDT address for current network
        address usdtAddress = USDTAddressProvider.getUSDTAddress();

        if (usdtAddress == address(0)) {
            console.log("USDT not available on chain", block.chainid);
            console.log("Network:", USDTAddressProvider.getCurrentNetworkName());
            console.log("Skipping fork tests - deploy MockUSDT for testing instead");
            return;
        }

        console.log("Running fork tests on:", USDTAddressProvider.getCurrentNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("USDT Address:", usdtAddress);

        usdt = IERC20(usdtAddress);

        // Deploy StableCoin
        stableCoin = new LocalCurrencyToken(
            usdtAddress,
            "Palestinian Shekel Digital",
            "PLSd",
            INITIAL_RATE,
            admin,
            address(0) // No oracle for fork tests
        );

        console.log("StableCoin deployed at:", address(stableCoin));

        // Fund test users from whale
        fundUsersFromWhale();
    }

    function configureWhaleAddresses() internal {
        // Ethereum Mainnet - Binance hot wallet
        whaleAddresses[1] = 0x28C6c06298d514Db089934071355E5743bf21d60;

        // Polygon - Binance hot wallet
        whaleAddresses[137] = 0x2cF7252e74036d1Da831d11089D326296e64a728;

        // Arbitrum - Binance hot wallet
        whaleAddresses[42161] = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;

        // Optimism - Binance hot wallet
        whaleAddresses[10] = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;

        // Base - Coinbase
        whaleAddresses[8453] = 0x4c80E24119CFB836cdF0a6b53dc23F04F7e652CA;

        // Avalanche - Binance hot wallet
        whaleAddresses[43114] = 0x9f8c163cBA728e99993ABe7495F06c0A3c8Ac8b9;

        // BSC - Binance hot wallet
        whaleAddresses[56] = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3;

        // Sepolia - USDT deployer/faucet
        whaleAddresses[11155111] = 0x4e71920b7330515faf5EA0c690f1aD06a85fB60c;

        // Polygon Mumbai - USDT deployer
        whaleAddresses[80001] = 0xdDc1B6E297B5D99a3f0b1fF3B8ac7dC49B1Fa26f;

        // BSC Testnet - USDT deployer
        whaleAddresses[97] = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd;
    }

    function fundUsersFromWhale() internal {
        address whale = whaleAddresses[block.chainid];

        if (whale == address(0)) {
            console.log("WARNING: No whale address configured for chain", block.chainid);
            console.log("Tests may fail if users can't be funded");
            return;
        }

        uint256 whaleBalance = usdt.balanceOf(whale);
        console.log("Whale balance:", whaleBalance);

        if (whaleBalance < 20000e6) {
            console.log("WARNING: Whale balance too low, some tests may fail");
            return;
        }

        // Impersonate whale and transfer USDT to test users
        vm.startPrank(whale);

        usdt.transfer(user1, 10000e6); // 10k USDT
        usdt.transfer(user2, 10000e6); // 10k USDT

        vm.stopPrank();

        console.log("User1 funded with:", usdt.balanceOf(user1));
        console.log("User2 funded with:", usdt.balanceOf(user2));
    }

    // ============ Skip if USDT not available ============

    modifier skipIfNoUSDT() {
        if (address(usdt) == address(0)) {
            console.log("Skipping test - USDT not available on this network");
            return;
        }
        _;
    }

    // ============ Basic Fork Tests ============

    function testFork_USDTExists() public skipIfNoUSDT {
        // Verify USDT contract exists and is valid
        assertTrue(address(usdt) != address(0), "USDT should be deployed");

        // Check USDT has supply
        assertGt(usdt.totalSupply(), 0, "USDT should have total supply");

        console.log("USDT Total Supply:", usdt.totalSupply());
        console.log("USDT Address:", address(usdt));
    }

    function testFork_MintWithRealUSDT() public skipIfNoUSDT {
        uint256 depositAmount = 1000e6; // 1000 USDT

        vm.startPrank(user1);

        // Approve and mint
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);

        vm.stopPrank();

        // Verify tokens received
        assertGt(ilsReceived, 0, "Should receive ILS tokens");
        assertEq(stableCoin.balanceOf(user1), ilsReceived, "User balance should match");

        // Verify USDT transferred
        assertEq(usdt.balanceOf(address(stableCoin)), depositAmount, "StableCoin should hold USDT");

        console.log("Deposited USDT:", depositAmount);
        console.log("Received ILS:", ilsReceived);
    }

    function testFork_RedeemWithRealUSDT() public skipIfNoUSDT {
        // First mint
        uint256 depositAmount = 1000e6;

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);

        // Then redeem
        uint256 usdtReceived = stableCoin.redeem(ilsReceived);
        vm.stopPrank();

        // Verify redemption
        assertEq(usdtReceived, depositAmount, "Should receive original USDT back");
        assertEq(stableCoin.balanceOf(user1), 0, "User should have no ILS tokens left");
        assertEq(usdt.balanceOf(user1), 10000e6, "User should have original USDT back");

        console.log("Redeemed USDT:", usdtReceived);
    }

    function testFork_MultipleUsersWithRealUSDT() public skipIfNoUSDT {
        uint256 deposit1 = 1000e6;
        uint256 deposit2 = 500e6;

        // User1 mints
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), deposit1);
        uint256 ils1 = stableCoin.mint(deposit1);
        vm.stopPrank();

        // User2 mints
        vm.startPrank(user2);
        usdt.approve(address(stableCoin), deposit2);
        uint256 ils2 = stableCoin.mint(deposit2);
        vm.stopPrank();

        // Verify balances
        assertEq(stableCoin.balanceOf(user1), ils1);
        assertEq(stableCoin.balanceOf(user2), ils2);
        assertEq(usdt.balanceOf(address(stableCoin)), deposit1 + deposit2);

        // User1 redeems half
        vm.prank(user1);
        stableCoin.redeem(ils1 / 2);

        // Verify remaining balances
        assertEq(stableCoin.balanceOf(user1), ils1 / 2);
        assertEq(stableCoin.balanceOf(user2), ils2);

        console.log("Multiple users test completed successfully");
    }

    function testFork_FeesWithRealUSDT() public skipIfNoUSDT {
        // Set 1% fees
        stableCoin.setMintFee(100);
        stableCoin.setRedeemFee(100);

        uint256 depositAmount = 1000e6;
        uint256 expectedMintFee = 10e6; // 1%

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Verify fee collected
        assertEq(stableCoin.totalFeesCollected(), expectedMintFee);

        // Verify net collateral
        assertEq(stableCoin.getNetCollateral(), depositAmount - expectedMintFee);

        // Withdraw fees
        address feeRecipient = address(0x999);
        stableCoin.withdrawFees(feeRecipient, expectedMintFee);

        // Verify withdrawal
        assertEq(usdt.balanceOf(feeRecipient), expectedMintFee);

        console.log("Fees collected and withdrawn successfully");
    }

    function testFork_LargeAmountWithRealUSDT() public skipIfNoUSDT {
        // Test with larger amount (if whale has enough)
        address whale = whaleAddresses[block.chainid];
        uint256 whaleBalance = usdt.balanceOf(whale);

        if (whaleBalance < 100000e6) {
            console.log("Skipping large amount test - whale balance too low");
            return;
        }

        uint256 largeAmount = 50000e6; // 50k USDT

        vm.startPrank(whale);
        usdt.transfer(user1, largeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), largeAmount);
        uint256 ilsReceived = stableCoin.mint(largeAmount);

        // Redeem half
        uint256 usdtReceived = stableCoin.redeem(ilsReceived / 2);
        vm.stopPrank();

        // Verify proportional redemption
        assertApproxEqRel(usdtReceived, largeAmount / 2, 0.001e18, "Should redeem half");

        console.log("Large amount test completed:", largeAmount);
    }

    // ============ Network-Specific Tests ============

    function testFork_CorrectNetworkDetection() public skipIfNoUSDT {
        string memory networkName = USDTAddressProvider.getCurrentNetworkName();

        console.log("Detected Network:", networkName);
        console.log("Chain ID:", block.chainid);

        assertTrue(bytes(networkName).length > 0, "Should detect network name");
        assertTrue(
            keccak256(bytes(networkName)) != keccak256(bytes("Unknown Network")),
            "Should be a known network"
        );
    }

    function testFork_CollateralRatioMaintained() public skipIfNoUSDT {
        // Multiple operations to verify collateral ratio stays at 100%
        vm.startPrank(user1);

        usdt.approve(address(stableCoin), 5000e6);
        stableCoin.mint(1000e6);
        stableCoin.mint(2000e6);
        stableCoin.mint(2000e6);

        vm.stopPrank();

        // Get collateral info
        (,, uint256 totalCollateral, uint256 netCollateral, uint256 collateralRatio,,,,,,) =
            stableCoin.getInfo();

        console.log("Total Collateral:", totalCollateral);
        console.log("Net Collateral:", netCollateral);
        console.log("Collateral Ratio:", collateralRatio);

        // Collateral ratio should be ~100% (10000 bps)
        assertApproxEqRel(collateralRatio, 10000, 0.01e18, "Collateral ratio should be 100%");
    }

    function testFork_RealUSDTTransferBehavior() public skipIfNoUSDT {
        // Some USDT implementations (especially on mainnet) have quirks
        // This test verifies our contract works with the real implementation

        uint256 amount = 100e6;

        vm.startPrank(user1);

        // Test approve and transfer
        usdt.approve(address(stableCoin), amount);
        uint256 allowance = usdt.allowance(user1, address(stableCoin));
        assertEq(allowance, amount, "Allowance should be set");

        // Mint (which does transferFrom)
        uint256 ilsReceived = stableCoin.mint(amount);

        // Verify transfer happened
        assertEq(usdt.balanceOf(address(stableCoin)), amount);
        assertGt(ilsReceived, 0);

        vm.stopPrank();

        console.log("Real USDT transfer behavior test passed");
    }

    // ============ Stress Tests on Fork ============

    function testFork_SequentialOperations() public skipIfNoUSDT {
        // Test many sequential operations
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 10000e6);

        for (uint i = 0; i < 10; i++) {
            stableCoin.mint(100e6);
        }

        uint256 balance = stableCoin.balanceOf(user1);

        for (uint i = 0; i < 5; i++) {
            stableCoin.redeem(balance / 10);
        }

        vm.stopPrank();

        // Verify contract is still solvent
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 netCollateral = stableCoin.getNetCollateral();
        uint256 requiredCollateral = stableCoin.previewRedeem(totalSupply);

        assertGe(netCollateral, requiredCollateral, "Contract should remain solvent");

        console.log("Sequential operations test passed");
    }

    // ============ Gas Benchmarking on Real Network ============

    function testFork_GasCosts() public skipIfNoUSDT {
        uint256 depositAmount = 1000e6;

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);

        // Measure mint gas
        uint256 gasBefore = gasleft();
        uint256 ilsReceived = stableCoin.mint(depositAmount);
        uint256 mintGas = gasBefore - gasleft();

        // Measure redeem gas
        gasBefore = gasleft();
        stableCoin.redeem(ilsReceived);
        uint256 redeemGas = gasBefore - gasleft();

        vm.stopPrank();

        console.log("=== Gas Costs on Real Network ===");
        console.log("Network:", USDTAddressProvider.getCurrentNetworkName());
        console.log("Mint gas:", mintGas);
        console.log("Redeem gas:", redeemGas);

        // Sanity checks (gas should be reasonable)
        assertLt(mintGas, 500000, "Mint gas should be reasonable");
        assertLt(redeemGas, 500000, "Redeem gas should be reasonable");
    }

    // ============ Helper Functions ============

    function logCurrentState() internal view {
        console.log("=== Current State ===");
        console.log("Network:", USDTAddressProvider.getCurrentNetworkName());
        console.log("Total Supply:", stableCoin.totalSupply());
        console.log("Total Collateral:", stableCoin.getTotalCollateral());
        console.log("Net Collateral:", stableCoin.getNetCollateral());
        console.log("Fees Collected:", stableCoin.totalFeesCollected());
    }
}
