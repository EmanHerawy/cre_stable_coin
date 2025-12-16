// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Converter.sol";
import "../src/PriceFeedReceiver.sol";

/**
 * @title ConverterTest
 * @notice Comprehensive unit tests for the Converter contract
 * @dev Tests rate management, oracle fallback, deviation protection, and admin functions
 */
contract ConverterTest is Test {
    Converter public converter;
    PriceFeedReceiver public priceFeedReceiver;

    address public admin;
    address public rateUpdater;
    address public pauser;
    address public user;
    address public forwarder;
    address public author;

    bytes32 public workflowId;
    bytes10 public workflowName;

    uint256 public constant INITIAL_RATE = 50e6; // 50 units per USDT
    uint256 public constant MAX_DEVIATION_BPS = 2000; // 20%
    uint256 public constant MAX_DEVIATION_LIMIT = 5000; // 50%
    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour

    event ManualPriceUpdated(uint256 oldRate, uint256 newRate, uint256 deviation, uint256 timestamp);
    event OraclePriceUpdated(uint256 oldRate, uint256 newRate, uint256 deviation, uint256 timestamp);
    event OracleToggled(bool indexed useOracle);
    event MaxDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);
    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);
    event PriceDeviationTooHigh(uint256 newRate, uint256 oldRate, uint256 deviationBps);
    event OracleFallbackActivated(uint256 timestamp, uint256 fallbackRate, string reason);

    function setUp() public {
        admin = address(this);
        rateUpdater = address(0x1);
        pauser = address(0x2);
        user = address(0x3);
        forwarder = address(0x4);
        author = address(0x5);

        workflowId = keccak256("workflow1");
        workflowName = bytes10("TEST");

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

        // Grant roles
        converter.grantRole(converter.RATE_UPDATER_ROLE(), rateUpdater);
        converter.grantRole(converter.PAUSER_ROLE(), pauser);
    }

    // ============ Constructor Tests ============

    function testConstructorSetsCorrectValues() public view {
        (uint256 manualRate, uint256 manualTimestamp, ) = converter.getManualPriceInfo();
        assertEq(manualRate, INITIAL_RATE);
        assertEq(manualTimestamp, block.timestamp);

        (uint256 oracleRate, uint256 oracleTimestamp, ) = converter.getOraclePriceInfo();
        assertEq(oracleRate, INITIAL_RATE);
        assertEq(oracleTimestamp, block.timestamp);

        assertEq(converter.useOracle(), true);
        assertEq(converter.maxPriceAge(), MAX_PRICE_AGE);
        assertEq(converter.maxPriceDeviationBps(), MAX_DEVIATION_BPS);
        assertEq(converter.MAX_DEVIATION_LIMIT(), MAX_DEVIATION_LIMIT);
        assertEq(address(converter.priceFeedReceiver()), address(priceFeedReceiver));
    }

    function testConstructorRevertsOnInvalidParams() public {
        // Zero initial rate
        vm.expectRevert(Converter.InvalidRate.selector);
        new Converter(0, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, admin, address(priceFeedReceiver));

        // Zero admin
        vm.expectRevert(Converter.InvalidAddress.selector);
        new Converter(INITIAL_RATE, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, address(0), address(priceFeedReceiver));

        // Zero max price age
        vm.expectRevert(Converter.InvalidPriceAge.selector);
        new Converter(INITIAL_RATE, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, 0, admin, address(priceFeedReceiver));

        // Zero max deviation limit
        vm.expectRevert();
        new Converter(INITIAL_RATE, MAX_DEVIATION_BPS, 0, MAX_PRICE_AGE, admin, address(priceFeedReceiver));

        // Deviation BPS exceeds limit
        vm.expectRevert();
        new Converter(INITIAL_RATE, 6000, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, admin, address(priceFeedReceiver));

        // Zero deviation BPS
        vm.expectRevert();
        new Converter(INITIAL_RATE, 0, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, admin, address(priceFeedReceiver));

        // Invalid rate (too high)
        vm.expectRevert(Converter.InvalidRate.selector);
        new Converter(2e9, MAX_DEVIATION_BPS, MAX_DEVIATION_LIMIT, MAX_PRICE_AGE, admin, address(priceFeedReceiver));
    }

    function testConstructorWithoutOracle() public {
        Converter converterNoOracle = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(0) // No oracle
        );

        assertEq(converterNoOracle.useOracle(), false);
        assertEq(address(converterNoOracle.priceFeedReceiver()), address(0));
    }

    // ============ Exchange Rate Calculation Tests ============

    function testGetExchangeRateMint() public view {
        // Test USDT → Local Currency
        uint256 usdtAmount = 100e6; // 100 USDT
        uint256 expectedLocal = (usdtAmount * INITIAL_RATE * 1e18) / 1e12;
        uint256 actualLocal = converter.getExchangeRate(true, usdtAmount);
        assertEq(actualLocal, expectedLocal);
    }

    function testGetExchangeRateRedeem() public view {
        // Test Local Currency → USDT
        uint256 localAmount = 5000e18; // 5000 tokens
        uint256 expectedUsdt = (localAmount * 1e12) / (INITIAL_RATE * 1e18);
        uint256 actualUsdt = converter.getExchangeRate(false, localAmount);
        assertEq(actualUsdt, expectedUsdt);
    }

    function testGetExchangeRateRoundTrip() public view {
        uint256 usdtAmount = 1000e6;
        uint256 localAmount = converter.getExchangeRate(true, usdtAmount);
        uint256 backToUsdt = converter.getExchangeRate(false, localAmount);

        assertApproxEqRel(backToUsdt, usdtAmount, 0.001e18); // 0.1% tolerance
    }

    function testGetExchangeRateEdgeCases() public view {
        // Minimum amounts
        uint256 minUsdt = 1; // 1 micro-USDT
        uint256 minLocal = converter.getExchangeRate(true, minUsdt);
        assertGt(minLocal, 0);

        // Large amounts
        uint256 largeUsdt = 1_000_000e6; // 1M USDT
        uint256 largeLocal = converter.getExchangeRate(true, largeUsdt);
        assertGt(largeLocal, 0);
    }

    // ============ Manual Rate Management Tests ============

    function testSetManualRate() public {
        converter.pause();

        uint256 newRate = 55e6;
        uint256 expectedDeviation = ((newRate - INITIAL_RATE) * 10000) / INITIAL_RATE;

        vm.expectEmit(true, true, true, true);
        emit ManualPriceUpdated(INITIAL_RATE, newRate, expectedDeviation, block.timestamp);
        emit OracleToggled(false);

        vm.prank(rateUpdater);
        converter.setManualRate(newRate);

        (uint256 rate, uint256 timestamp, uint256 deviation) = converter.getManualPriceInfo();
        assertEq(rate, newRate);
        assertEq(timestamp, block.timestamp);
        assertEq(deviation, expectedDeviation);
        assertEq(converter.useOracle(), false);
    }

    function testSetManualRateRevertsWhenNotPaused() public {
        vm.prank(rateUpdater);
        vm.expectRevert();
        converter.setManualRate(55e6);
    }

    function testSetManualRateRevertsOnZeroRate() public {
        converter.pause();
        vm.prank(rateUpdater);
        vm.expectRevert(Converter.InvalidRate.selector);
        converter.setManualRate(0);
    }

    function testSetManualRateRevertsOnInvalidRate() public {
        converter.pause();
        vm.prank(rateUpdater);
        vm.expectRevert(Converter.InvalidRate.selector);
        converter.setManualRate(2e9);
    }

    function testSetManualRateAccessControl() public {
        converter.pause();
        vm.prank(user);
        vm.expectRevert();
        converter.setManualRate(55e6);
    }

    // ============ Oracle Mode Tests ============

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

    function testToggleUseOracleRevertsWhenNotPaused() public {
        vm.expectRevert();
        converter.toggleUseOracle();
    }

    function testToggleUseOracleAccessControl() public {
        converter.pause();
        vm.prank(user);
        vm.expectRevert();
        converter.toggleUseOracle();
    }

    // ============ Oracle Price Update Tests ============

    function testOraclePriceUpdate() public {
        uint224 newPrice = 52e6;
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(newPrice, timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Fetch the price which should update oracle price
        uint256 rate = converter.getExchangeRateView();
        assertEq(rate, newPrice);
    }

    function testOracleFallbackOnStalePrice() public {
        vm.warp(10000);

        uint224 price = 52e6;
        uint32 oldTimestamp = uint32(block.timestamp - MAX_PRICE_AGE - 1);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(price, oldTimestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Should fallback to manual rate
        uint256 rate = converter.getExchangeRateView();
        assertEq(rate, INITIAL_RATE);
    }

    function testOracleFallbackOnZeroPrice() public {
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

    function testOracleFallbackOnExcessiveDeviation() public {
        // Set initial oracle price
        uint224 initialPrice = 50e6;
        uint32 timestamp1 = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report1 = abi.encode(initialPrice, timestamp1);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report1);

        // Trigger oracle price fetch to update oraclePrice
        converter.getExchangeRateView();

        // Try to set price with >20% deviation
        vm.warp(block.timestamp + 100);
        uint224 deviatedPrice = 70e6; // 40% increase
        uint32 timestamp2 = uint32(block.timestamp);
        bytes memory report2 = abi.encode(deviatedPrice, timestamp2);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report2);

        // Should fallback to manual rate
        uint256 rate = converter.getExchangeRateView();
        assertEq(rate, INITIAL_RATE);
    }

    function testOracleFallbackWhenNotConfigured() public {
        Converter converterNoOracle = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(0)
        );

        uint256 rate = converterNoOracle.getExchangeRateView();
        assertEq(rate, INITIAL_RATE);
    }

    // ============ Deviation Calculation Tests ============

    function testDeviationCalculation() public {
        // 10% increase: 50 → 55
        converter.pause();
        vm.prank(rateUpdater);
        converter.setManualRate(55e6);

        (, , uint256 deviation) = converter.getManualPriceInfo();
        assertEq(deviation, 1000); // 10% = 1000 bps

        // 10% decrease: 55 → 49.5
        vm.prank(rateUpdater);
        converter.setManualRate(495e5);

        (, , deviation) = converter.getManualPriceInfo();
        assertEq(deviation, 1000); // 10% = 1000 bps
    }

    // ============ Admin Configuration Tests ============

    function testSetMaxPriceDeviation() public {
        converter.pause();

        uint256 newDeviation = 3000; // 30%
        vm.expectEmit(true, true, true, true);
        emit MaxDeviationUpdated(MAX_DEVIATION_BPS, newDeviation);

        converter.setMaxPriceDeviation(newDeviation);

        assertEq(converter.maxPriceDeviationBps(), newDeviation);
    }

    function testSetMaxPriceDeviationRevertsWhenExceedsLimit() public {
        converter.pause();
        vm.expectRevert();
        converter.setMaxPriceDeviation(6000); // Exceeds MAX_DEVIATION_LIMIT (5000)
    }

    function testSetMaxPriceDeviationRevertsOnZero() public {
        converter.pause();
        vm.expectRevert();
        converter.setMaxPriceDeviation(0);
    }

    function testSetMaxPriceAge() public {
        converter.pause();

        uint256 newAge = 7200; // 2 hours
        vm.expectEmit(true, true, true, true);
        emit MaxPriceAgeUpdated(MAX_PRICE_AGE, newAge);

        converter.setMaxPriceAge(newAge);

        assertEq(converter.maxPriceAge(), newAge);
    }

    function testSetMaxPriceAgeRevertsOnZero() public {
        converter.pause();
        vm.expectRevert(Converter.InvalidPriceAge.selector);
        converter.setMaxPriceAge(0);
    }

    function testSetPriceFeedReceiver() public {
        PriceFeedReceiver newReceiver = new PriceFeedReceiver(admin);

        converter.pause();
        converter.setPriceFeedReceiver(address(newReceiver));

        assertEq(address(converter.priceFeedReceiver()), address(newReceiver));
    }

    function testSetPriceFeedReceiverRevertsOnZeroAddress() public {
        converter.pause();
        vm.expectRevert(Converter.InvalidAddress.selector);
        converter.setPriceFeedReceiver(address(0));
    }

    function testSetPriceFeedReceiverRevertsOnSameAddress() public {
        converter.pause();
        vm.expectRevert(Converter.InvalidAddress.selector);
        converter.setPriceFeedReceiver(address(priceFeedReceiver));
    }

    // ============ Pause/Unpause Tests ============

    function testPauseUnpause() public {
        assertEq(converter.paused(), false);

        vm.prank(pauser);
        converter.pause();
        assertEq(converter.paused(), true);

        vm.prank(pauser);
        converter.unpause();
        assertEq(converter.paused(), false);
    }

    function testPauseAccessControl() public {
        vm.prank(user);
        vm.expectRevert();
        converter.pause();
    }

    // ============ View Function Tests ============

    function testGetLastPriceUpdate() public {
        // Initially returns manual price timestamp
        uint256 lastUpdateBefore = converter.getLastPriceUpdate();
        assertEq(lastUpdateBefore, block.timestamp);

        // After oracle update
        vm.warp(block.timestamp + 100);
        uint224 price = 52e6;
        uint32 timestamp = uint32(block.timestamp);
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(price, timestamp);

        vm.prank(forwarder);
        priceFeedReceiver.onReport(metadata, report);

        // Trigger oracle fetch
        converter.getExchangeRateView();

        uint256 lastUpdateAfter = converter.getLastPriceUpdate();
        // View-based oracle fetch does not change stored timestamps; it should remain the same
        assertEq(lastUpdateAfter, lastUpdateBefore);
    }

    function testIsPriceStale() public {
        // Fresh price
        assertEq(converter.isPriceStale(), false);

        // Warp past max age
        vm.warp(block.timestamp + MAX_PRICE_AGE + 1);
        assertEq(converter.isPriceStale(), true);
    }

    function testGetOraclePriceInfo() public {
        (uint256 rate, uint256 timestamp, uint256 deviation) = converter.getOraclePriceInfo();
        assertEq(rate, INITIAL_RATE);
        assertEq(timestamp, block.timestamp);
        assertEq(deviation, 0);
    }

    function testGetManualPriceInfo() public {
        (uint256 rate, uint256 timestamp, uint256 deviation) = converter.getManualPriceInfo();
        assertEq(rate, INITIAL_RATE);
        assertEq(timestamp, block.timestamp);
        assertEq(deviation, 0);
    }

    // ============ Fuzzing Tests ============

    function testFuzz_ExchangeRateConversion(uint96 usdtAmount) public view {
        vm.assume(usdtAmount > 0);
        vm.assume(usdtAmount < 1_000_000_000e6); // Reasonable upper bound

        uint256 localAmount = converter.getExchangeRate(true, usdtAmount);
        assertGt(localAmount, 0);

        uint256 backToUsdt = converter.getExchangeRate(false, localAmount);
        assertApproxEqRel(backToUsdt, usdtAmount, 0.01e18); // 1% tolerance
    }

    function testFuzz_SetManualRate(uint96 newRate) public {
        vm.assume(newRate > 0);
        vm.assume(newRate < 1e9);

        converter.pause();
        vm.prank(rateUpdater);
        converter.setManualRate(newRate);

        (uint256 rate, , ) = converter.getManualPriceInfo();
        assertEq(rate, newRate);
    }

    function testFuzz_DeviationCalculation(uint96 rate1, uint96 rate2) public {
        vm.assume(rate1 > 0 && rate1 < 1e9);
        vm.assume(rate2 > 0 && rate2 < 1e9);

        converter.pause();
        vm.prank(rateUpdater);
        converter.setManualRate(rate1);

        vm.prank(rateUpdater);
        converter.setManualRate(rate2);

        (, , uint256 deviation) = converter.getManualPriceInfo();

        // Calculate expected deviation
        uint256 expectedDeviation;
        if (rate2 > rate1) {
            expectedDeviation = ((rate2 - rate1) * 10000) / rate1;
        } else {
            expectedDeviation = ((rate1 - rate2) * 10000) / rate1;
        }

        assertEq(deviation, expectedDeviation);
    }
}
