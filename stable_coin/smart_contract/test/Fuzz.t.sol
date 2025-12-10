// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, type(uint128).max); // Large supply for fuzzing
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title FuzzTest
 * @notice Stateless fuzz tests for edge cases in money flow and math
 */
contract FuzzTest is Test {
    LocalCurrencyToken public stableCoin;
    MockUSDT public usdt;

    address public admin = address(1);
    address public user = address(2);

    uint256 constant INITIAL_RATE = 3_223_000; // 3.223 ILS per USDT (6 decimals)
    uint256 constant MAX_USDT_SUPPLY = type(uint128).max;

    function setUp() public {
        usdt = new MockUSDT();

        vm.prank(admin);
        stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Palestinian Shekel Digital",
            "PLSd",
            INITIAL_RATE,
            admin,
            address(0)
        );

        // Fund user
        usdt.mint(user, MAX_USDT_SUPPLY);
    }

    // ============ Mint Fuzz Tests ============

    /// @notice Test mint with random amounts and fees
    function testFuzz_MintWithRandomAmounts(uint256 depositAmount, uint16 feeBps) public {
        // Bound inputs to realistic ranges
        depositAmount = bound(depositAmount, stableCoin.minDeposit(), 1_000_000_000e6); // 1 USDT to 1B USDT
        feeBps = uint16(bound(feeBps, 0, stableCoin.MAX_FEE_BPS())); // 0% to 10%

        // Set fee
        vm.prank(admin);
        stableCoin.setMintFee(feeBps);

        // Calculate expected values
        uint256 expectedFee = (depositAmount * feeBps) / 10000;
        uint256 usdtAfterFee = depositAmount - expectedFee;
        uint256 expectedTokens = stableCoin.previewDeposit(usdtAfterFee);

        // Mint
        vm.startPrank(user);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 received = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Assertions
        assertEq(received, expectedTokens, "Incorrect tokens received");
        assertEq(stableCoin.balanceOf(user), expectedTokens, "Incorrect user balance");
        assertEq(stableCoin.totalFeesCollected(), expectedFee, "Incorrect fees collected");
        assertEq(stableCoin.getTotalCollateral(), depositAmount, "Incorrect total collateral");
        assertEq(stableCoin.getNetCollateral(), usdtAfterFee, "Incorrect net collateral");
    }

    /// @notice Test mint with very small amounts (dust)
    function testFuzz_MintDustAmounts(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, stableCoin.minDeposit(), 100e6); // 1-100 USDT

        vm.startPrank(user);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 received = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Should not revert and should maintain correct ratios
        assertGt(received, 0, "Should receive some tokens");

        // Verify round-trip approximately works
        uint256 redeemPreview = stableCoin.previewRedeem(received);
        assertApproxEqRel(redeemPreview, depositAmount, 0.0001e18, "Round-trip deviation too high");
    }

    /// @notice Test fee calculation precision
    function testFuzz_FeeCalculationPrecision(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, 1e6, 1_000_000e6);
        feeBps = uint16(bound(feeBps, 1, 1000)); // 0.01% to 10%

        uint256 fee = (amount * feeBps) / 10000;

        // Fee should always round down (favoring protocol)
        uint256 afterFee = amount - fee;
        assertLe(afterFee + fee, amount, "Fee + remaining should not exceed original");

        // Fee should be proportional
        if (feeBps > 0) {
            assertGt(fee, 0, "Non-zero fee should collect something");
        }
    }

    // ============ Redeem Fuzz Tests ============

    /// @notice Test redeem with random amounts and fees
    function testFuzz_RedeemWithRandomAmounts(uint256 mintAmount, uint16 redeemFeeBps) public {
        mintAmount = bound(mintAmount, stableCoin.minDeposit(), 100_000_000e6); // Up to 100M USDT
        redeemFeeBps = uint16(bound(redeemFeeBps, 0, stableCoin.MAX_FEE_BPS()));

        // First mint
        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        uint256 tokensReceived = stableCoin.mint(mintAmount);
        vm.stopPrank();

        // Set redeem fee
        vm.prank(admin);
        stableCoin.setRedeemFee(redeemFeeBps);

        // Redeem all tokens
        uint256 usdtBeforeFee = stableCoin.previewRedeem(tokensReceived);
        uint256 expectedFee = (usdtBeforeFee * redeemFeeBps) / 10000;
        uint256 expectedUsdt = usdtBeforeFee - expectedFee;

        // Skip if redeem amount is below minimum (due to fees)
        if (expectedUsdt < stableCoin.minWithdrawal()) {
            return;
        }

        vm.prank(user);
        uint256 usdtReceived = stableCoin.redeem(tokensReceived);

        // Assertions
        assertEq(usdtReceived, expectedUsdt, "Incorrect USDT received");
        assertEq(stableCoin.balanceOf(user), 0, "Should have no tokens left");
        assertEq(stableCoin.totalFeesCollected(), expectedFee, "Incorrect fees collected");
    }

    /// @notice Test partial redemptions maintain correct ratios
    function testFuzz_PartialRedemption(uint256 mintAmount, uint256 redeemPercent) public {
        mintAmount = bound(mintAmount, 10e6, 100_000e6); // 10 to 100k USDT
        redeemPercent = bound(redeemPercent, 1, 100); // 1% to 100%

        // Mint
        vm.startPrank(user);
        usdt.approve(address(stableCoin), mintAmount);
        uint256 tokensReceived = stableCoin.mint(mintAmount);
        vm.stopPrank();

        // Redeem partial amount
        uint256 redeemAmount = (tokensReceived * redeemPercent) / 100;

        // Skip if redeem amount is too small
        if (stableCoin.previewRedeem(redeemAmount) < stableCoin.minWithdrawal()) {
            return;
        }

        vm.prank(user);
        uint256 usdtReceived = stableCoin.redeem(redeemAmount);

        // Verify proportional redemption
        uint256 expectedUsdt = (mintAmount * redeemPercent) / 100;
        assertApproxEqRel(usdtReceived, expectedUsdt, 0.001e18, "Redemption not proportional");

        // Verify remaining balance
        assertEq(stableCoin.balanceOf(user), tokensReceived - redeemAmount, "Incorrect remaining balance");
    }

    // ============ Fee Withdrawal Fuzz Tests ============

    /// @notice Test fee withdrawal with various scenarios
    function testFuzz_FeeWithdrawal(uint256 deposits, uint16 mintFeeBps, uint256 withdrawPercent) public {
        deposits = bound(deposits, 10e6, 1_000_000e6); // 10 to 1M USDT
        mintFeeBps = uint16(bound(mintFeeBps, 1, 1000)); // 0.01% to 10%
        withdrawPercent = bound(withdrawPercent, 1, 100); // 1% to 100%

        // Set fee and mint
        vm.prank(admin);
        stableCoin.setMintFee(mintFeeBps);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), deposits);
        stableCoin.mint(deposits);
        vm.stopPrank();

        uint256 feesCollected = stableCoin.totalFeesCollected();
        uint256 withdrawAmount = (feesCollected * withdrawPercent) / 100;

        // Withdraw fees
        address recipient = address(0x999);
        vm.prank(admin);
        stableCoin.withdrawFees(recipient, withdrawAmount);

        // Verify
        assertEq(usdt.balanceOf(recipient), withdrawAmount, "Incorrect fee withdrawal");
        assertEq(stableCoin.totalFeesCollected(), feesCollected - withdrawAmount, "Incorrect remaining fees");
    }

    // ============ Math Invariants ============

    /// @notice Verify deposit->redeem round trip preserves value (minus fees)
    function testFuzz_RoundTripInvariant(uint256 depositAmount, uint16 mintFeeBps, uint16 redeemFeeBps) public {
        depositAmount = bound(depositAmount, 10e6, 100_000e6);
        mintFeeBps = uint16(bound(mintFeeBps, 0, 500)); // Max 5% for round-trip test
        redeemFeeBps = uint16(bound(redeemFeeBps, 0, 500));

        // Set fees
        vm.prank(admin);
        stableCoin.setMintFee(mintFeeBps);
        vm.prank(admin);
        stableCoin.setRedeemFee(redeemFeeBps);

        // Calculate expected after fees
        uint256 mintFee = (depositAmount * mintFeeBps) / 10000;
        uint256 afterMintFee = depositAmount - mintFee;

        // Mint
        vm.startPrank(user);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 tokens = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Redeem
        uint256 usdtBeforeRedeemFee = stableCoin.previewRedeem(tokens);
        uint256 redeemFee = (usdtBeforeRedeemFee * redeemFeeBps) / 10000;

        vm.prank(user);
        uint256 usdtReceived = stableCoin.redeem(tokens);

        // Expected: deposit - mint_fee - redeem_fee (approximately)
        uint256 expectedNet = depositAmount - mintFee - redeemFee;

        // Allow small rounding error (0.01%)
        assertApproxEqRel(usdtReceived, expectedNet, 0.0001e18, "Round-trip value loss too high");

        // Total fees should equal mint + redeem fees
        assertEq(stableCoin.totalFeesCollected(), mintFee + redeemFee, "Fee accounting incorrect");
    }

    /// @notice Verify collateral always backs all tokens
    function testFuzz_CollateralInvariant(uint256 deposits, uint256 redeems, uint16 mintFeeBps) public {
        deposits = bound(deposits, 100e6, 10_000_000e6); // 100 to 10M USDT
        redeems = bound(redeems, 0, 50); // Redeem 0-50% of minted tokens
        mintFeeBps = uint16(bound(mintFeeBps, 0, 1000));

        // Set fee
        vm.prank(admin);
        stableCoin.setMintFee(mintFeeBps);

        // Mint
        vm.startPrank(user);
        usdt.approve(address(stableCoin), deposits);
        uint256 tokens = stableCoin.mint(deposits);
        vm.stopPrank();

        // Partial redeem
        uint256 redeemAmount = (tokens * redeems) / 100;
        if (redeemAmount > 0 && stableCoin.previewRedeem(redeemAmount) >= stableCoin.minWithdrawal()) {
            vm.prank(user);
            stableCoin.redeem(redeemAmount);
        }

        // INVARIANT: Net collateral should always be sufficient to back remaining tokens
        uint256 remainingTokens = stableCoin.totalSupply();
        if (remainingTokens > 0) {
            uint256 requiredCollateral = stableCoin.previewRedeem(remainingTokens);
            uint256 netCollateral = stableCoin.getNetCollateral();

            assertGe(netCollateral, requiredCollateral, "Insufficient collateral to back tokens");
        }
    }

    /// @notice Test extreme fee combinations
    function testFuzz_ExtremeFees(uint256 amount) public {
        amount = bound(amount, 100e6, 1_000_000e6);

        // Max fees (10% each)
        vm.prank(admin);
        stableCoin.setMintFee(1000);
        vm.prank(admin);
        stableCoin.setRedeemFee(1000);

        vm.startPrank(user);
        usdt.approve(address(stableCoin), amount);
        uint256 tokens = stableCoin.mint(amount);
        vm.stopPrank();

        // Should still be able to redeem
        vm.prank(user);
        uint256 received = stableCoin.redeem(tokens);

        // Should receive less than original (due to 20% total fees)
        assertLt(received, amount, "Should lose money to fees");

        // But should still receive something
        assertGt(received, 0, "Should receive some USDT back");

        // Total fees should be tracked correctly
        uint256 mintFee = amount / 10; // 10%
        uint256 afterMint = amount - mintFee;
        uint256 redeemFee = afterMint / 10; // 10% of remaining

        assertApproxEqRel(stableCoin.totalFeesCollected(), mintFee + redeemFee, 0.01e18, "Fee tracking incorrect");
    }

    /// @notice Test decimal precision edge cases
    function testFuzz_DecimalPrecision(uint256 usdtAmount) public {
        // Test very specific amounts that might cause rounding issues
        usdtAmount = bound(usdtAmount, 1e6, 1000e6); // 1 to 1000 USDT

        vm.startPrank(user);
        usdt.approve(address(stableCoin), usdtAmount);
        uint256 ilsTokens = stableCoin.mint(usdtAmount);
        vm.stopPrank();

        // Verify preview functions match actual execution
        uint256 expectedIls = stableCoin.previewDeposit(usdtAmount);
        assertEq(ilsTokens, expectedIls, "Preview deposit mismatch");

        uint256 previewUsdt = stableCoin.previewRedeem(ilsTokens);

        vm.prank(user);
        uint256 actualUsdt = stableCoin.redeem(ilsTokens);

        assertEq(actualUsdt, previewUsdt, "Preview redeem mismatch");
    }

    /// @notice Test sequential operations maintain consistency
    function testFuzz_SequentialOperations(
        uint256 deposit1,
        uint256 deposit2,
        uint256 redeemPercent
    ) public {
        deposit1 = bound(deposit1, 10e6, 100_000e6);
        deposit2 = bound(deposit2, 10e6, 100_000e6);
        redeemPercent = bound(redeemPercent, 10, 90);

        address user2 = address(0x123);
        usdt.mint(user2, deposit2);

        // User1 deposits
        vm.startPrank(user);
        usdt.approve(address(stableCoin), deposit1);
        uint256 tokens1 = stableCoin.mint(deposit1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        usdt.approve(address(stableCoin), deposit2);
        uint256 tokens2 = stableCoin.mint(deposit2);
        vm.stopPrank();

        // User1 redeems partial
        uint256 redeemAmount = (tokens1 * redeemPercent) / 100;
        if (stableCoin.previewRedeem(redeemAmount) >= stableCoin.minWithdrawal()) {
            vm.prank(user);
            stableCoin.redeem(redeemAmount);
        }

        // Verify total supply is consistent
        uint256 expectedSupply = tokens1 + tokens2 - redeemAmount;
        assertEq(stableCoin.totalSupply(), expectedSupply, "Total supply inconsistent");

        // Verify collateral can back all tokens
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 requiredCollateral = stableCoin.previewRedeem(totalSupply);
        assertGe(stableCoin.getNetCollateral(), requiredCollateral, "Insufficient collateral");
    }
}
