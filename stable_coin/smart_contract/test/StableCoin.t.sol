// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
import "../src/PriceFeedReceiver.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

// Mock USDT token for testing
contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {
        _mint(msg.sender, 1000000 * 10**6); // 1M USDT with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LocalCurrencyTokenTest is Test {
    LocalCurrencyToken public stableCoin;
    PriceFeedReceiver public priceFeedReceiver;
    MockUSDT public usdt;

    address public admin;
    address public user1;
    address public user2;
    address public forwarder;
    address public author;

    bytes32 public workflowId;
    bytes10 public workflowName;

    uint256 public constant INITIAL_RATE = 50e6; // 50 EGP per USDT

    event Minted(address indexed user, uint256 usdtAmount, uint256 localCurrencyAmount, uint256 fee);
    event Redeemed(address indexed user, uint256 localCurrencyAmount, uint256 usdtAmount, uint256 fee);
    event RateUpdated(uint256 oldRate, uint256 newRate, bool isOracle);
    event OracleToggled(bool useOracle);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        forwarder = address(0x3);
        author = address(0x4);

        workflowId = keccak256("workflow1");
        workflowName = bytes10("USD_EGP");

        // Deploy mock USDT
        usdt = new MockUSDT();

        // Deploy PriceFeedReceiver
        priceFeedReceiver = new PriceFeedReceiver(admin);
        priceFeedReceiver.addKeystoneForwarder(forwarder);
        priceFeedReceiver.addExpectedWorkflowId(workflowId);
        priceFeedReceiver.addExpectedAuthor(author);
        priceFeedReceiver.addExpectedWorkflowName(workflowName);

        // Deploy StableCoin
        stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Egyptian Pound Digital",
            "EGPd",
            INITIAL_RATE,
            admin,
            address(priceFeedReceiver)
        );

        // Fund test users
        usdt.mint(user1, 10000e6); // 10,000 USDT
        usdt.mint(user2, 10000e6);
    }

    // ============ Constructor Tests ============

    function testInitialState() public view {
        assertEq(address(stableCoin.usdt()), address(usdt));
        assertEq(address(stableCoin.priceFeedReceiver()), address(priceFeedReceiver));
        assertEq(stableCoin.manualRate(), INITIAL_RATE);
        assertEq(stableCoin.useOracle(), true);
        assertEq(stableCoin.minDeposit(), 1e6);
        assertEq(stableCoin.minWithdrawal(), 1e6);
        assertEq(stableCoin.maxPriceAge(), 3600);
        assertEq(stableCoin.name(), "Egyptian Pound Digital");
        assertEq(stableCoin.symbol(), "EGPd");
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        new LocalCurrencyToken(
            address(0), // Invalid USDT address
            "Test",
            "TST",
            INITIAL_RATE,
            admin,
            address(priceFeedReceiver)
        );

        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        new LocalCurrencyToken(
            address(usdt),
            "Test",
            "TST",
            INITIAL_RATE,
            address(0), // Invalid admin address
            address(priceFeedReceiver)
        );
    }

    function testConstructorRevertsOnZeroRate() public {
        vm.expectRevert(LocalCurrencyToken.InvalidRate.selector);
        new LocalCurrencyToken(
            address(usdt),
            "Test",
            "TST",
            0, // Invalid rate
            admin,
            address(priceFeedReceiver)
        );
    }

    // ============ Mint Tests ============

    function testMintWithManualRate() public {
        // Pause and toggle to manual rate
        stableCoin.pause();
        stableCoin.toggleUseOracle();
        stableCoin.unpause();

        uint256 depositAmount = 1000e6; // 1000 USDT
        uint256 expectedTokens = (depositAmount * INITIAL_RATE * 1e18) / 1e12; // 50,000 * 1e18

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Minted(user1, depositAmount, expectedTokens, 0); // 0 fee

        uint256 received = stableCoin.mint(depositAmount);
        vm.stopPrank();

        assertEq(received, expectedTokens);
        assertEq(stableCoin.balanceOf(user1), expectedTokens);
        assertEq(stableCoin.getTotalCollateral(), depositAmount);
    }

    function testMintWithOracleRate() public {
        // Set oracle price
        uint224 oraclePrice = 5000000000; // 50.00 with 8 decimals
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(oraclePrice, timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Mint tokens
        uint256 depositAmount = 1000e6;
        uint256 expectedTokens = (depositAmount * INITIAL_RATE * 1e18) / 1e12;

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 received = stableCoin.mint(depositAmount);
        vm.stopPrank();

        assertEq(received, expectedTokens);
        assertEq(stableCoin.balanceOf(user1), expectedTokens);
    }

    function testMintRevertsWhenBelowMinimum() public {
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 0.5e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                LocalCurrencyToken.DepositBelowMinimum.selector,
                0.5e6,
                1e6
            )
        );
        stableCoin.mint(0.5e6);
        vm.stopPrank();
    }

    function testMintRevertsWhenPaused() public {
        stableCoin.pause();

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        vm.expectRevert();
        stableCoin.mint(1000e6);
        vm.stopPrank();
    }

    // ============ Redeem Tests ============

    function testRedeem() public {
        // First mint tokens
        uint256 depositAmount = 1000e6;

        stableCoin.pause();
        stableCoin.toggleUseOracle();
        stableCoin.unpause();

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 mintedTokens = stableCoin.mint(depositAmount);

        // Now redeem half
        uint256 redeemAmount = mintedTokens / 2;
        uint256 expectedUsdt = stableCoin.previewRedeem(redeemAmount);

        vm.expectEmit(true, true, true, true);
        emit Redeemed(user1, redeemAmount, expectedUsdt, 0); // 0 fee

        uint256 receivedUsdt = stableCoin.redeem(redeemAmount);
        vm.stopPrank();

        assertEq(receivedUsdt, expectedUsdt);
        assertEq(stableCoin.balanceOf(user1), mintedTokens - redeemAmount);
    }

    function testRedeemRevertsWhenBelowMinimum() public {
        // Mint tokens first
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);

        // Try to redeem very small amount
        uint256 smallAmount = 100; // Will be less than minWithdrawal in USDT
        vm.expectRevert();
        stableCoin.redeem(smallAmount);
        vm.stopPrank();
    }

    function testRedeemRevertsWhenInsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert(LocalCurrencyToken.InvalidAmount.selector);
        stableCoin.redeem(1000e18);
        vm.stopPrank();
    }

    function testRedeemRevertsWhenPaused() public {
        // Mint tokens first
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        uint256 mintedTokens = stableCoin.mint(1000e6);
        vm.stopPrank();

        stableCoin.pause();

        vm.startPrank(user1);
        vm.expectRevert();
        stableCoin.redeem(mintedTokens);
        vm.stopPrank();
    }

    // ============ Rate Management Tests ============

    function testUpdateManualRate() public {
        stableCoin.pause();

        uint256 newRate = 55e6;
        vm.expectEmit(true, true, true, true);
        emit RateUpdated(INITIAL_RATE, newRate, false);

        stableCoin.updateManualRate(newRate);

        assertEq(stableCoin.manualRate(), newRate);
        assertGt(stableCoin.lastManualRateUpdate(), 0);
    }

    function testUpdateManualRateRevertsWhenNotPaused() public {
        vm.expectRevert();
        stableCoin.updateManualRate(55e6);
    }

    function testUpdateManualRateRevertsOnZeroRate() public {
        stableCoin.pause();
        vm.expectRevert(LocalCurrencyToken.InvalidRate.selector);
        stableCoin.updateManualRate(0);
    }

    function testToggleUseOracle() public {
        stableCoin.pause();

        assertEq(stableCoin.useOracle(), true);

        vm.expectEmit(true, true, true, true);
        emit OracleToggled(false);
        stableCoin.toggleUseOracle();

        assertEq(stableCoin.useOracle(), false);

        vm.expectEmit(true, true, true, true);
        emit OracleToggled(true);
        stableCoin.toggleUseOracle();

        assertEq(stableCoin.useOracle(), true);
    }

    function testToggleUseOracleRevertsWhenNotPaused() public {
        vm.expectRevert();
        stableCoin.toggleUseOracle();
    }

    // ============ Oracle Tests ============

    function testOracleFallbackOnStaleData() public {
        // Warp time forward first
        vm.warp(10000);

        // Set oracle price with old timestamp
        uint224 oraclePrice = 5000000000;
        uint32 oldTimestamp = uint32(block.timestamp - 7200); // 2 hours ago
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(oraclePrice, oldTimestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Should fallback to manual rate
        uint256 rate = stableCoin.getExchangeRate();
        assertEq(rate, INITIAL_RATE);
    }

    function testOracleFallbackOnZeroPrice() public {
        // Set oracle price to zero
        uint224 zeroPrice = 0;
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(zeroPrice, timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Should fallback to manual rate
        uint256 rate = stableCoin.getExchangeRate();
        assertEq(rate, INITIAL_RATE);
    }

    function testGetLastPriceUpdate() public {
        // Set oracle price
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(uint224(5000000000), timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        uint256 lastUpdate = stableCoin.getLastPriceUpdate();
        assertEq(lastUpdate, timestamp);
    }

    function testIsPriceStale() public {
        // Initially no data
        assertEq(stableCoin.isPriceStale(), true);

        // Set fresh oracle price
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(uint224(5000000000), timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        assertEq(stableCoin.isPriceStale(), false);

        // Advance time beyond maxPriceAge
        vm.warp(block.timestamp + 3601);
        assertEq(stableCoin.isPriceStale(), true);
    }

    // ============ Admin Function Tests ============

    function testSetPriceFeedReceiver() public {
        PriceFeedReceiver newReceiver = new PriceFeedReceiver(admin);

        stableCoin.pause();

        vm.expectEmit(true, true, true, true);
        emit PriceFeedUpdated(address(priceFeedReceiver), address(newReceiver));

        stableCoin.setPriceFeedReceiver(address(newReceiver));

        assertEq(address(stableCoin.priceFeedReceiver()), address(newReceiver));
    }

    function testSetPriceFeedReceiverRevertsWhenNotPaused() public {
        PriceFeedReceiver newReceiver = new PriceFeedReceiver(admin);
        vm.expectRevert();
        stableCoin.setPriceFeedReceiver(address(newReceiver));
    }

    function testSetPriceFeedReceiverRevertsOnZeroAddress() public {
        stableCoin.pause();
        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        stableCoin.setPriceFeedReceiver(address(0));
    }

    function testSetPriceFeedReceiverRevertsOnSameAddress() public {
        stableCoin.pause();
        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        stableCoin.setPriceFeedReceiver(address(priceFeedReceiver));
    }

    function testSetMaxPriceAge() public {
        uint256 newAge = 7200;
        stableCoin.setMaxPriceAge(newAge);
        assertEq(stableCoin.maxPriceAge(), newAge);
    }

    function testSetMaxPriceAgeRevertsOnZero() public {
        vm.expectRevert(LocalCurrencyToken.InvalidPriceAge.selector);
        stableCoin.setMaxPriceAge(0);
    }

    function testSetMinDeposit() public {
        uint256 newMin = 10e6;
        stableCoin.setMinDeposit(newMin);
        assertEq(stableCoin.minDeposit(), newMin);
    }

    function testSetMinDepositRevertsOnZero() public {
        vm.expectRevert(LocalCurrencyToken.InvalidMinimumAmount.selector);
        stableCoin.setMinDeposit(0);
    }

    function testSetMinWithdrawal() public {
        uint256 newMin = 10e6;
        stableCoin.setMinWithdrawal(newMin);
        assertEq(stableCoin.minWithdrawal(), newMin);
    }

    function testSetMinWithdrawalRevertsOnZero() public {
        vm.expectRevert(LocalCurrencyToken.InvalidMinimumAmount.selector);
        stableCoin.setMinWithdrawal(0);
    }

    // ============ Pause/Unpause Tests ============

    function testPauseUnpause() public {
        assertEq(stableCoin.paused(), false);

        stableCoin.pause();
        assertEq(stableCoin.paused(), true);

        stableCoin.unpause();
        assertEq(stableCoin.paused(), false);
    }

    // ============ Preview Functions Tests ============

    function testPreviewDeposit() public {
        uint256 usdtAmount = 1000e6;
        uint256 expected = (usdtAmount * INITIAL_RATE * 1e18) / 1e12;
        uint256 preview = stableCoin.previewDeposit(usdtAmount);
        assertEq(preview, expected);
    }

    function testPreviewRedeem() public {
        uint256 localAmount = 50000e18; // 50,000 tokens
        uint256 expected = (localAmount * 1e12) / (INITIAL_RATE * 1e18);
        uint256 preview = stableCoin.previewRedeem(localAmount);
        assertEq(preview, expected);
    }

    // ============ View Functions Tests ============

    function testGetTotalCollateral() public {
        assertEq(stableCoin.getTotalCollateral(), 0);

        // Mint some tokens
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);
        vm.stopPrank();

        assertEq(stableCoin.getTotalCollateral(), 1000e6);
    }

    function testGetInfo() public {
        // Set oracle price
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(uint224(5000000000), timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Mint some tokens
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);
        vm.stopPrank();

        (
            uint256 currentRate,
            uint256 totalSupply_,
            uint256 collateral,
            uint256 netCollateral,
            uint256 collateralRatio,
            bool usingOracle,
            uint256 lastUpdate,
            bool priceIsStale,
            uint256 feesCollected,
            uint256 mintFee,
            uint256 redeemFee
        ) = stableCoin.getInfo();

        assertEq(currentRate, INITIAL_RATE);
        assertGt(totalSupply_, 0);
        assertEq(collateral, 1000e6);
        assertEq(netCollateral, 1000e6); // No fees collected yet
        assertApproxEqRel(collateralRatio, 10000, 0.01e18); // ~100% with 1% tolerance
        assertEq(usingOracle, true);
        assertEq(lastUpdate, timestamp);
        assertEq(priceIsStale, false);
        assertEq(feesCollected, 0); // No fees initially
        assertEq(mintFee, 0); // 0% fee
        assertEq(redeemFee, 0); // 0% fee
    }

    // ============ Direct Balance Tests ============

    function testDirectUSDTTransfer() public {
        // User accidentally sends USDT directly
        vm.prank(user1);
        usdt.transfer(address(stableCoin), 500e6);

        // Should be reflected in collateral
        assertEq(stableCoin.getTotalCollateral(), 500e6);
    }

    // ============ Access Control Tests ============

    function testOnlyAdminCanSetPriceFeed() public {
        stableCoin.pause();
        PriceFeedReceiver newReceiver = new PriceFeedReceiver(admin);

        vm.prank(user1);
        vm.expectRevert();
        stableCoin.setPriceFeedReceiver(address(newReceiver));
    }

    function testOnlyAdminCanToggleOracle() public {
        stableCoin.pause();

        vm.prank(user1);
        vm.expectRevert();
        stableCoin.toggleUseOracle();
    }

    function testOnlyRateUpdaterCanUpdateManualRate() public {
        stableCoin.pause();

        vm.prank(user1);
        vm.expectRevert();
        stableCoin.updateManualRate(55e6);
    }

    function testOnlyPauserCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        stableCoin.pause();
    }
}
