// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
import "../src/Converter.sol";
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
    Converter public converter;
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
    uint256 public constant MAX_DEVIATION_BPS = 2000; // 20%
    uint256 public constant MAX_DEVIATION_LIMIT = 5000; // 50%
    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour

    event Minted(address indexed user, uint256 usdtAmount, uint256 localCurrencyAmount, uint256 fee);
    event Redeemed(address indexed user, uint256 localCurrencyAmount, uint256 usdtAmount, uint256 fee);
    event OracleToggled(bool indexed useOracle);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event ManualPriceUpdated(uint256 oldRate, uint256 newRate, uint256 deviation, uint256 timestamp);
    event OraclePriceUpdated(uint256 oldRate, uint256 newRate, uint256 deviation, uint256 timestamp);

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

        // Deploy Converter
        converter = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(priceFeedReceiver)
        );

        // Deploy StableCoin
        stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Egyptian Pound Digital",
            "EGPd",
            address(converter),
            admin
        );

        // Fund test users
        usdt.mint(user1, 10000e6); // 10,000 USDT
        usdt.mint(user2, 10000e6);
    }

    // ============ Constructor Tests ============

    function testInitialState() public view {
        assertEq(address(stableCoin.usdt()), address(usdt));
        assertEq(address(stableCoin.converter()), address(converter));
        assertEq(stableCoin.minDeposit(), 1e6);
        assertEq(stableCoin.minWithdrawal(), 1e6);
        assertEq(stableCoin.name(), "Egyptian Pound Digital");
        assertEq(stableCoin.symbol(), "EGPd");

        // Converter state
        assertEq(converter.useOracle(), true);
        assertEq(converter.maxPriceAge(), MAX_PRICE_AGE);
        assertEq(converter.maxPriceDeviationBps(), MAX_DEVIATION_BPS);
        assertEq(converter.MAX_DEVIATION_LIMIT(), MAX_DEVIATION_LIMIT);
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        new LocalCurrencyToken(
            address(0), // Invalid USDT address
            "Test",
            "TST",
            address(converter),
            admin
        );

        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        new LocalCurrencyToken(
            address(usdt),
            "Test",
            "TST",
            address(0), // Invalid converter address
            admin
        );

        vm.expectRevert(LocalCurrencyToken.InvalidAddress.selector);
        new LocalCurrencyToken(
            address(usdt),
            "Test",
            "TST",
            address(converter),
            address(0) // Invalid admin address
        );
    }

    function testConverterConstructorRevertsOnInvalidParams() public {
        // Zero initial rate
        vm.expectRevert(Converter.InvalidRate.selector);
        new Converter(0, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, admin, address(priceFeedReceiver));

        // Zero admin
        vm.expectRevert(Converter.InvalidAddress.selector);
        new Converter(INITIAL_RATE, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, address(0), address(priceFeedReceiver));

        // Zero max price age
        vm.expectRevert(Converter.InvalidPriceAge.selector);
        new Converter(INITIAL_RATE, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, 0, admin, address(priceFeedReceiver));

        // Deviation BPS exceeds limit
        vm.expectRevert();
        new Converter(INITIAL_RATE, 6000, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, admin, address(priceFeedReceiver));
    }

    // ============ Mint Tests ============

    function testMintWithManualRate() public {
        // Toggle to manual rate
        converter.pause();
        converter.toggleUseOracle();
        converter.unpause();

        uint256 depositAmount = 1000e6; // 1000 USDT
        uint256 expectedTokens = converter.getExchangeRate(true, depositAmount);

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
        uint224 oraclePrice = 50e6; // 50.00 with 6 decimals
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(oraclePrice, timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Mint tokens
        uint256 depositAmount = 1000e6;
        uint256 expectedTokens = converter.getExchangeRate(true, depositAmount);

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

    function testMintWithFees() public {
        // Set 1% mint fee
        stableCoin.setMintFee(100);

        uint256 depositAmount = 1000e6;
        uint256 fee = (depositAmount * 100) / 10000; // 10 USDT fee
        uint256 usdtAfterFee = depositAmount - fee;
        uint256 expectedTokens = converter.getExchangeRate(true, usdtAfterFee);

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 received = stableCoin.mint(depositAmount);
        vm.stopPrank();

        assertEq(received, expectedTokens);
        assertEq(stableCoin.totalFeesToBeCollected(), fee);
    }

    // ============ Redeem Tests ============

    function testRedeem() public {
        // First mint tokens
        uint256 depositAmount = 1000e6;

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 mintedTokens = stableCoin.mint(depositAmount);

        // Now redeem half
        uint256 redeemAmount = mintedTokens / 2;
        uint256 expectedUsdt = converter.getExchangeRate(false, redeemAmount);

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

    function testRedeemWithFees() public {
        // Set 1% redeem fee
        stableCoin.setRedeemFee(100);

        // Mint tokens first
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        uint256 mintedTokens = stableCoin.mint(1000e6);

        // Redeem all
        uint256 usdtBeforeFee = converter.getExchangeRate(false, mintedTokens);
        uint256 fee = (usdtBeforeFee * 100) / 10000;
        uint256 expectedUsdt = usdtBeforeFee - fee;

        uint256 receivedUsdt = stableCoin.redeem(mintedTokens);
        vm.stopPrank();

        assertEq(receivedUsdt, expectedUsdt);
        assertEq(stableCoin.totalFeesToBeCollected(), fee);
    }

    // ============ Converter Rate Management Tests ============

    function testSetManualRate() public {
        converter.pause();

        uint256 newRate = 55e6;
        vm.expectEmit(true, true, true, true);
        emit ManualPriceUpdated(INITIAL_RATE, newRate, ((newRate - INITIAL_RATE) * 10000) / INITIAL_RATE, block.timestamp);

        converter.setManualRate(newRate);
        converter.unpause();

        (uint256 rate, , ) = converter.getManualPriceInfo();
        assertEq(rate, newRate);
        assertEq(converter.useOracle(), false); // Switches to manual mode
    }

    function testSetManualRateRevertsWhenNotPaused() public {
        vm.expectRevert();
        converter.setManualRate(55e6);
    }

    function testSetManualRateRevertsOnZeroRate() public {
        converter.pause();
        vm.expectRevert(Converter.InvalidRate.selector);
        converter.setManualRate(0);
    }

    function testSetManualRateRevertsOnInvalidRate() public {
        converter.pause();
        vm.expectRevert(Converter.InvalidRate.selector);
        converter.setManualRate(2e9); // Too high
    }

    function testToggleUseOracle() public {
        converter.pause();

        assertEq(converter.useOracle(), true);

        vm.expectEmit(true, true, true, true);
        emit OracleToggled(false);
        converter.toggleUseOracle();

        assertEq(converter.useOracle(), false);

        vm.expectEmit(true, true, true, true);
        emit OracleToggled(true);
        converter.toggleUseOracle();

        assertEq(converter.useOracle(), true);
    }

    // ============ Oracle Tests ============

    function testOracleFallbackOnStaleData() public {
        // Set oracle price with old timestamp
        vm.warp(10000);
        uint224 oraclePrice = 50e6;
        uint32 oldTimestamp = uint32(block.timestamp - 7200); // 2 hours ago
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(oraclePrice, oldTimestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Should fallback to manual rate
        uint256 rate = converter.getExchangeRateView();
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
        uint256 rate = converter.getExchangeRateView();
        assertEq(rate, INITIAL_RATE);
    }

    function testOracleDeviationProtection() public {
        // Set initial oracle price
        uint224 initialPrice = 50e6;
        uint32 timestamp1 = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report1 = abi.encode(initialPrice, timestamp1);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report1);

        // Try to set price with >20% deviation (should fallback to manual)
        vm.warp(block.timestamp + 100);
        uint224 deviatedPrice = 70e6; // 40% increase
        uint32 timestamp2 = uint32(block.timestamp);
        bytes memory report2 = abi.encode(deviatedPrice, timestamp2);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report2);

        // Should fallback to manual rate due to deviation
        uint256 rate = converter.getExchangeRateView();
        assertEq(rate, INITIAL_RATE);
    }

    function testGetLastPriceUpdate() public {
        // Set oracle price
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(uint224(50e6), timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        uint256 lastUpdate = converter.getLastPriceUpdate();
        assertEq(lastUpdate, timestamp);
    }

    function testIsPriceStale() public {
        // Initially using manual rate (timestamp from constructor)
        assertEq(converter.isPriceStale(), false);

        // Set fresh oracle price
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(uint224(50e6), timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        assertEq(converter.isPriceStale(), false);

        // Advance time beyond maxPriceAge
        vm.warp(block.timestamp + 3601);
        assertEq(converter.isPriceStale(), true);
    }

    // ============ Admin Function Tests ============

    function testSetConverter() public {
        Converter newConverter = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(priceFeedReceiver)
        );

        stableCoin.pause();
        stableCoin.setConverter(address(newConverter));
        stableCoin.unpause();

        assertEq(address(stableCoin.converter()), address(newConverter));
    }

    function testSetConverterRevertsWhenNotPaused() public {
        Converter newConverter = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(priceFeedReceiver)
        );

        vm.expectRevert();
        stableCoin.setConverter(address(newConverter));
    }

    function testSetPriceFeedReceiver() public {
        PriceFeedReceiver newReceiver = new PriceFeedReceiver(admin);

        converter.pause();
        converter.setPriceFeedReceiver(address(newReceiver));
        converter.unpause();

        assertEq(address(converter.priceFeedReceiver()), address(newReceiver));
    }

    function testWithdrawFees() public {
        // Set mint fee
        stableCoin.setMintFee(100); // 1%

        // Mint to collect fees
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);
        vm.stopPrank();

        uint256 feesCollected = stableCoin.totalFeesToBeCollected();
        assertGt(feesCollected, 0);

        uint256 recipientBalanceBefore = usdt.balanceOf(admin);
        stableCoin.withdrawFees(admin, feesCollected);
        uint256 recipientBalanceAfter = usdt.balanceOf(admin);

        assertEq(recipientBalanceAfter - recipientBalanceBefore, feesCollected);
        assertEq(stableCoin.totalFeesToBeCollected(), 0);
    }

    function testWithdrawFeesRevertsWhenInsufficientBacking() public {
        // This test ensures fees can't be withdrawn if it would break collateralization
        stableCoin.setMintFee(100); // 1%

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);
        vm.stopPrank();

        uint256 feesCollected = stableCoin.totalFeesToBeCollected();

        // Try to withdraw more than available fees
        vm.expectRevert();
        stableCoin.withdrawFees(admin, feesCollected + 1);
    }

    // ============ Decimal Conversion Tests ============

    function testDecimalConversions() public view {
        // Test USDT (6 decimals) → Local Currency (18 decimals)
        uint256 usdtAmount = 100e6; // 100 USDT
        uint256 expectedLocal = (usdtAmount * INITIAL_RATE * 1e18) / 1e12;
        uint256 actualLocal = converter.getExchangeRate(true, usdtAmount);
        assertEq(actualLocal, expectedLocal);

        // Test Local Currency (18 decimals) → USDT (6 decimals)
        uint256 localAmount = 5000e18; // 5000 tokens
        uint256 expectedUsdt = (localAmount * 1e12) / (INITIAL_RATE * 1e18);
        uint256 actualUsdt = converter.getExchangeRate(false, localAmount);
        assertEq(actualUsdt, expectedUsdt);
    }

    function testRoundTripConversion() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 mintedTokens = stableCoin.mint(depositAmount);

        uint256 receivedUsdt = stableCoin.redeem(mintedTokens);
        vm.stopPrank();

        // Should get back the same amount (within rounding error)
        assertApproxEqRel(receivedUsdt, depositAmount, 0.001e18); // 0.1% tolerance
    }

    // ============ Access Control Tests ============

    function testOnlyAdminCanSetConverter() public {
        Converter newConverter = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(priceFeedReceiver)
        );

        stableCoin.pause();
        vm.prank(user1);
        vm.expectRevert();
        stableCoin.setConverter(address(newConverter));
    }

    function testOnlyAdminCanToggleOracle() public {
        converter.pause();
        vm.prank(user1);
        vm.expectRevert();
        converter.toggleUseOracle();
    }

    function testOnlyRateUpdaterCanSetManualRate() public {
        converter.pause();
        vm.prank(user1);
        vm.expectRevert();
        converter.setManualRate(55e6);
    }

    // ============ View Functions Tests ============

    function testGetInfo() public {
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
            uint256 feesCollected,
            uint256 mintFee,
            uint256 redeemFee,
            address converterAddress
        ) = stableCoin.getInfo();

        assertEq(currentRate, INITIAL_RATE);
        assertGt(totalSupply_, 0);
        assertEq(collateral, 1000e6);
        assertEq(netCollateral, 1000e6); // No fees collected yet
        assertEq(feesCollected, 0);
        assertEq(mintFee, 0);
        assertEq(redeemFee, 0);
        assertEq(converterAddress, address(converter));
    }
}
