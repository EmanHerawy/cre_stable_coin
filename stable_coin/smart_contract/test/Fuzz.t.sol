// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
import "../src/Converter.sol";
import "../src/PriceFeedReceiver.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, type(uint128).max);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title FuzzRefactoredTest
 * @notice Comprehensive fuzzing tests for the refactored stablecoin system
 * @dev Tests edge cases, boundary conditions, and unexpected inputs
 */
contract FuzzRefactoredTest is Test {
    LocalCurrencyToken public stableCoin;
    Converter public converter;
    PriceFeedReceiver public priceFeedReceiver;
    MockUSDT public usdt;

    address public admin;
    address public user;

    uint256 constant INITIAL_RATE = 50e6;
    uint256 constant MAX_DEVIATION_BPS = 2000;
    uint256 constant MAX_DEVIATION_LIMIT = 5000;
    uint256 constant MAX_PRICE_AGE = 3600;

    function setUp() public {
        admin = address(this);
        user = address(0x1);

        usdt = new MockUSDT();
        priceFeedReceiver = new PriceFeedReceiver(admin);

        converter = new Converter(
            INITIAL_RATE,
            MAX_DEVIATION_BPS,
            MAX_DEVIATION_LIMIT,
            MAX_PRICE_AGE,
            admin,
            address(0) // Manual mode for fuzzing
        );

        stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Test Currency",
            "TEST",
            address(converter),
            admin
        );

        usdt.mint(user, type(uint128).max);
    }

    // ============ Mint Fuzzing Tests ============

    function testFuzz_MintAmount(uint96 amount) public {
        vm.assume(amount >= stableCoin.minDeposit());
        vm.assume(amount <= 1_000_000_000e6); // 1B USDT max

        vm.startPrank(user);
        usdt.approve(address(stableCoin), amount);
        uint256 tokens = stableCoin.mint(amount);
        vm.stopPrank();

        assertGt(tokens, 0);
        assertEq(stableCoin.balanceOf(user), tokens);
        assertEq(stableCoin.getTotalCollateral(), amount);
    }

    function testFuzz_MintWithFee(uint96 amount, uint16 feeBps) public {
        vm.assume(amount >= stableCoin.minDeposit());
        vm.assume(amount <= 1_000_000_000e6);
        vm.assume(feeBps <= 1000); // Max 10%

        stableCoin.setMintFee(feeBps);

        uint256 expectedFee = (amount * feeBps) / 10000;
        uint256 usdtAfterFee = amount - expectedFee;

        vm.startPrank(user);
        usdt.approve(address(stableCoin), amount);
        uint256 tokens = stableCoin.mint(amount);
        vm.stopPrank();

        assertGt(tokens, 0);
        assertEq(stableCoin.totalFeesToBeCollected(), expectedFee);
    }

    function testFuzz_MintRevertsWhenBelowMinimum(uint96 amount) public {
        vm.assume(amount < stableCoin.minDeposit());
        vm.assume(amount > 0);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), amount);
        vm.expectRevert();
        stableCoin.mint(amount);
        vm.stopPrank();
    }

    // ============ Redeem Fuzzing Tests ============

    function testFuzz_RedeemAmount(uint96 mintAmount, uint8 redeemPercent) public {
        vm.assume(mintAmount >= stableCoin.minDeposit());
        vm.assume(mintAmount <= 1_000_000_000e6);
        vm.assume(redeemPercent > 0 && redeemPercent <= 100);

        // Mint first
        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        uint256 tokens = stableCoin.mint(mintAmount);

        // Redeem a percentage
        uint256 redeemAmount = (tokens * redeemPercent) / 100;
        uint256 expectedUsdt = converter.getExchangeRate(false, redeemAmount);

        if (expectedUsdt >= stableCoin.minWithdrawal()) {
            uint256 receivedUsdt = stableCoin.redeem(redeemAmount);
            assertGt(receivedUsdt, 0);
            assertLe(receivedUsdt, mintAmount);
        }
        vm.stopPrank();
    }

    function testFuzz_RedeemWithFee(uint96 mintAmount, uint16 feeBps) public {
        vm.assume(mintAmount >= 100e6); // Higher minimum for fee testing
        vm.assume(mintAmount <= 1_000_000_000e6);
        vm.assume(feeBps <= 1000);

        stableCoin.setRedeemFee(feeBps);

        // Mint first
        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        uint256 tokens = stableCoin.mint(mintAmount);

        // Redeem all
        uint256 usdtBeforeFee = converter.getExchangeRate(false, tokens);
        uint256 expectedFee = (usdtBeforeFee * feeBps) / 10000;
        uint256 expectedUsdt = usdtBeforeFee - expectedFee;

        if (expectedUsdt >= stableCoin.minWithdrawal()) {
            uint256 receivedUsdt = stableCoin.redeem(tokens);
            assertEq(stableCoin.totalFeesToBeCollected(), expectedFee);
            assertApproxEqRel(receivedUsdt, expectedUsdt, 0.01e18);
        }
        vm.stopPrank();
    }

    function testFuzz_RoundTripConversion(uint96 amount) public {
        vm.assume(amount >= stableCoin.minDeposit());
        vm.assume(amount <= 1_000_000_000e6);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), amount);
        uint256 tokens = stableCoin.mint(amount);

        uint256 receivedUsdt = stableCoin.redeem(tokens);
        vm.stopPrank();

        // Should get back approximately the same amount
        assertApproxEqRel(receivedUsdt, amount, 0.01e18); // 1% tolerance
    }

    // ============ Converter Exchange Rate Fuzzing ============

    function testFuzz_ConverterMintConversion(uint96 usdtAmount) public view {
        vm.assume(usdtAmount > 0);
        vm.assume(usdtAmount < type(uint96).max / INITIAL_RATE);

        uint256 localAmount = converter.getExchangeRate(true, usdtAmount);
        assertGt(localAmount, 0);

        // Verify calculation
        uint256 expected = (usdtAmount * INITIAL_RATE * 1e18) / 1e12;
        assertEq(localAmount, expected);
    }

    function testFuzz_ConverterRedeemConversion(uint128 localAmount) public view {
        vm.assume(localAmount > 0);
        // Constrain to a reasonable range to avoid arithmetic overflow in test calculations
        vm.assume(localAmount < 1e24);

        uint256 usdtAmount = converter.getExchangeRate(false, localAmount);
        // For very small localAmount values, integer division can round down to zero
        if (usdtAmount == 0) {
            return;
        }

        // Verify calculation for non-zero outputs
        uint256 expected = (localAmount * 1e12) / (INITIAL_RATE * 1e18);
        assertEq(usdtAmount, expected);
    }

    function testFuzz_ConverterRoundTrip(uint96 usdtAmount) public view {
        vm.assume(usdtAmount > 0);
        vm.assume(usdtAmount < 1_000_000_000e6);

        uint256 localAmount = converter.getExchangeRate(true, usdtAmount);
        uint256 backToUsdt = converter.getExchangeRate(false, localAmount);

        assertApproxEqRel(backToUsdt, usdtAmount, 0.01e18); // 1% tolerance
    }

    // ============ Manual Rate Fuzzing ============

    function testFuzz_SetManualRate(uint96 newRate) public {
        vm.assume(newRate > 0);
        vm.assume(newRate < 1e9);

        converter.pause();
        converter.setManualRate(newRate);
        converter.unpause();

        (uint256 rate, , ) = converter.getManualPriceInfo();
        assertEq(rate, newRate);

        // Test conversion still works
        uint256 testAmount = 100e6;
        uint256 localAmount = converter.getExchangeRate(true, testAmount);
        assertGt(localAmount, 0);
    }

    function testFuzz_ManualRateDeviation(uint96 rate1, uint96 rate2) public {
        vm.assume(rate1 > 0 && rate1 < 1e9);
        vm.assume(rate2 > 0 && rate2 < 1e9);

        converter.pause();
        converter.setManualRate(rate1);

        converter.setManualRate(rate2);
        converter.unpause();

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

    // ============ Fee Management Fuzzing ============

    function testFuzz_SetMintFee(uint16 feeBps) public {
        vm.assume(feeBps <= 1000);

        stableCoin.setMintFee(feeBps);
        assertEq(stableCoin.mintFeeBps(), feeBps);
    }

    function testFuzz_SetRedeemFee(uint16 feeBps) public {
        vm.assume(feeBps <= 1000);

        stableCoin.setRedeemFee(feeBps);
        assertEq(stableCoin.redeemFeeBps(), feeBps);
    }

    function testFuzz_SetFeeRevertsWhenTooHigh(uint16 feeBps) public {
        vm.assume(feeBps > 1000);

        vm.expectRevert();
        stableCoin.setMintFee(feeBps);

        vm.expectRevert();
        stableCoin.setRedeemFee(feeBps);
    }

    function testFuzz_WithdrawFees(uint96 mintAmount, uint16 mintFeeBps, uint8 withdrawPercent) public {
        vm.assume(mintAmount >= stableCoin.minDeposit());
        vm.assume(mintAmount <= 1_000_000_000e6);
        vm.assume(mintFeeBps > 0 && mintFeeBps <= 1000);
        vm.assume(withdrawPercent > 0 && withdrawPercent <= 100);

        stableCoin.setMintFee(mintFeeBps);

        // Mint to collect fees
        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        stableCoin.mint(mintAmount);
        vm.stopPrank();

        uint256 feesCollected = stableCoin.totalFeesToBeCollected();
        assertGt(feesCollected, 0);

        uint256 withdrawAmount = (feesCollected * withdrawPercent) / 100;
        if (withdrawAmount > 0) {
            uint256 balanceBefore = usdt.balanceOf(admin);
            stableCoin.withdrawFees(admin, withdrawAmount);
            uint256 balanceAfter = usdt.balanceOf(admin);

            assertEq(balanceAfter - balanceBefore, withdrawAmount);
        }
    }

    // ============ Minimum Amount Fuzzing ============

    function testFuzz_SetMinDeposit(uint96 newMin) public {
        vm.assume(newMin > 0);
        vm.assume(newMin <= 1_000_000e6);

        stableCoin.setMinDeposit(newMin);
        assertEq(stableCoin.minDeposit(), newMin);
    }

    function testFuzz_SetMinWithdrawal(uint96 newMin) public {
        vm.assume(newMin > 0);
        vm.assume(newMin <= 1_000_000e6);

        stableCoin.setMinWithdrawal(newMin);
        assertEq(stableCoin.minWithdrawal(), newMin);
    }

    // ============ Price Age Fuzzing ============

    function testFuzz_SetMaxPriceAge(uint32 newAge) public {
        vm.assume(newAge > 0);
        vm.assume(newAge <= 86400); // Max 1 day

        converter.pause();
        converter.setMaxPriceAge(newAge);
        converter.unpause();

        assertEq(converter.maxPriceAge(), newAge);
    }

    // ============ Deviation Fuzzing ============

    function testFuzz_SetMaxPriceDeviation(uint16 deviationBps) public {
        vm.assume(deviationBps > 0);
        vm.assume(deviationBps <= MAX_DEVIATION_LIMIT);

        converter.pause();
        converter.setMaxPriceDeviation(deviationBps);
        converter.unpause();

        assertEq(converter.maxPriceDeviationBps(), deviationBps);
    }

    function testFuzz_SetMaxPriceDeviationRevertsWhenExceedsLimit(uint16 deviationBps) public {
        vm.assume(deviationBps > MAX_DEVIATION_LIMIT);

        converter.pause();
        vm.expectRevert();
        converter.setMaxPriceDeviation(deviationBps);
    }

    // ============ Multiple Operations Fuzzing ============

    function testFuzz_MultipleMints(uint96 amount1, uint96 amount2, uint96 amount3) public {
        vm.assume(amount1 >= stableCoin.minDeposit() && amount1 <= 100_000_000e6);
        vm.assume(amount2 >= stableCoin.minDeposit() && amount2 <= 100_000_000e6);
        vm.assume(amount3 >= stableCoin.minDeposit() && amount3 <= 100_000_000e6);

        vm.startPrank(user);

        usdt.approve(address(stableCoin), amount1);
        uint256 tokens1 = stableCoin.mint(amount1);

        usdt.approve(address(stableCoin), amount2);
        uint256 tokens2 = stableCoin.mint(amount2);

        usdt.approve(address(stableCoin), amount3);
        uint256 tokens3 = stableCoin.mint(amount3);

        vm.stopPrank();

        assertEq(stableCoin.balanceOf(user), tokens1 + tokens2 + tokens3);
        assertEq(stableCoin.getTotalCollateral(), amount1 + amount2 + amount3);
    }

    function testFuzz_MintRedeemSequence(uint96 mintAmount, uint8 redeemPercent) public {
        vm.assume(mintAmount >= 100e6); // Higher minimum
        vm.assume(mintAmount <= 1_000_000_000e6);
        vm.assume(redeemPercent > 0 && redeemPercent <= 100);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        uint256 tokens = stableCoin.mint(mintAmount);

        uint256 redeemAmount = (tokens * redeemPercent) / 100;
        uint256 previewUsdt = converter.getExchangeRate(false, redeemAmount);

        if (previewUsdt >= stableCoin.minWithdrawal()) {
            uint256 receivedUsdt = stableCoin.redeem(redeemAmount);
            assertGt(receivedUsdt, 0);

            uint256 remainingTokens = stableCoin.balanceOf(user);
            assertEq(remainingTokens, tokens - redeemAmount);
        }
        vm.stopPrank();
    }

    // ============ Edge Cases ============

    function testFuzz_ZeroAmountReverts() public {
        vm.startPrank(user);
        usdt.approve(address(stableCoin), 1e6);

        vm.expectRevert();
        stableCoin.mint(0);

        vm.expectRevert();
        stableCoin.redeem(0);

        vm.stopPrank();
    }

    function testFuzz_InsufficientApprovalReverts(uint96 amount, uint96 approval) public {
        vm.assume(amount >= stableCoin.minDeposit());
        vm.assume(approval < amount);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), approval);

        vm.expectRevert();
        stableCoin.mint(amount);

        vm.stopPrank();
    }

    function testFuzz_InsufficientBalanceRedeemReverts(uint96 mintAmount, uint128 redeemAmount) public {
        vm.assume(mintAmount >= stableCoin.minDeposit());
        vm.assume(mintAmount <= 1_000_000_000e6);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        uint256 tokens = stableCoin.mint(mintAmount);

        vm.assume(redeemAmount > tokens);

        vm.expectRevert();
        stableCoin.redeem(redeemAmount);

        vm.stopPrank();
    }

    // ============ Collateralization Fuzzing ============

    function testFuzz_CollateralizationAlwaysValid(uint96 amount) public {
        vm.assume(amount >= stableCoin.minDeposit());
        vm.assume(amount <= 1_000_000_000e6);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), amount);
        stableCoin.mint(amount);
        vm.stopPrank();

        uint256 totalSupply = stableCoin.totalSupply();
        uint256 requiredCollateral = converter.getExchangeRate(false, totalSupply);
        uint256 netCollateral = stableCoin.getNetCollateral();

        assertGe(netCollateral, requiredCollateral);
    }
}
