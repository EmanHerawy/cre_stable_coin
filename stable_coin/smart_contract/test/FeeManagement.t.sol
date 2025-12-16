// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
import "../src/Converter.sol";
import "../src/PriceFeedReceiver.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000e6); // 1M USDT
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @title FeeManagementTest
 * @notice Comprehensive tests for fee collection system
 * @dev Tests mint fees, redeem fees, and fee withdrawal functionality
 */
contract FeeManagementTest is Test {
    LocalCurrencyToken public stableCoin;
    Converter public converter;
    PriceFeedReceiver public priceFeedReceiver;
    MockUSDT public usdt;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public feeRecipient = address(4);

    uint256 constant INITIAL_RATE = 3_223_000; // 3.223 ILS per USDT (6 decimals)

    function setUp() public {
        // Deploy mock USDT
        usdt = new MockUSDT();

        // Deploy PriceFeedReceiver (with admin as owner)
        vm.prank(admin);
        priceFeedReceiver = new PriceFeedReceiver(admin);

        // Deploy Converter with manual rate
        vm.prank(admin);
        converter = new Converter(
            INITIAL_RATE,      // manual rate
            2000,              // 20% max deviation
            5000,              // 50% hard cap
            3600,              // 1 hour max price age
            admin,             // owner
            address(priceFeedReceiver)
        );

        // Deploy stablecoin with Converter
        vm.prank(admin);
        stableCoin = new LocalCurrencyToken(
            address(usdt),
            "Palestinian Shekel Digital",
            "PLSd",
            address(converter),
            admin
        );

        // Fund users with USDT
        usdt.transfer(user1, 10000e6); // 10k USDT
        usdt.transfer(user2, 10000e6); // 10k USDT
    }

    // ============ Fee Configuration Tests ============

    function testSetMintFee() public {
        vm.prank(admin);
        stableCoin.setMintFee(100); // 1%

        assertEq(stableCoin.mintFeeBps(), 100);
    }

    function testSetRedeemFee() public {
        vm.prank(admin);
        stableCoin.setRedeemFee(50); // 0.5%

        assertEq(stableCoin.redeemFeeBps(), 50);
    }

    function testCannotSetFeeTooHigh() public {
        vm.prank(admin);
        vm.expectRevert();
        stableCoin.setMintFee(1001); // > 10%
    }

    function testOnlyAdminCanSetFees() public {
        vm.prank(user1);
        vm.expectRevert();
        stableCoin.setMintFee(100);
    }

    // ============ Mint Fee Tests ============

    function testMintWithFee() public {
        // Set 1% mint fee
        vm.prank(admin);
        stableCoin.setMintFee(100);

        uint256 depositAmount = 1000e6; // 1000 USDT
        uint256 expectedFee = 10e6; // 1% = 10 USDT
        uint256 expectedUsdtAfterFee = 990e6; // 990 USDT

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Check tokens received based on amount after fee
        uint256 expectedIls = converter.getExchangeRate(true, expectedUsdtAfterFee);
        assertEq(ilsReceived, expectedIls);

        // Check fees collected
        assertEq(stableCoin.totalFeesToBeCollected(), expectedFee);

        // Check total collateral includes fees
        assertEq(stableCoin.getTotalCollateral(), depositAmount);

        // Check net collateral excludes fees
        assertEq(stableCoin.getNetCollateral(), expectedUsdtAfterFee);
    }

    function testMintWithZeroFee() public {
        // No fee set (default 0%)
        uint256 depositAmount = 1000e6;

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Should receive full amount
        uint256 expectedIls = converter.getExchangeRate(true, depositAmount);
        assertEq(ilsReceived, expectedIls);

        // No fees collected
        assertEq(stableCoin.totalFeesToBeCollected(), 0);
    }

    // ============ Redeem Fee Tests ============

    function testRedeemWithFee() public {
        // First mint some tokens (no fee on mint)
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Set 2% redeem fee
        vm.prank(admin);
        stableCoin.setRedeemFee(200);

        // Redeem half
        uint256 redeemAmount = ilsReceived / 2;
        uint256 usdtBeforeFee = converter.getExchangeRate(false, redeemAmount);
        uint256 expectedFee = (usdtBeforeFee * 200) / 10000; // 2%
        uint256 expectedUsdtAfterFee = usdtBeforeFee - expectedFee;

        vm.prank(user1);
        uint256 usdtReceived = stableCoin.redeem(redeemAmount);

        // Check USDT received after fee
        assertEq(usdtReceived, expectedUsdtAfterFee);

        // Check fees collected
        assertEq(stableCoin.totalFeesToBeCollected(), expectedFee);
    }

    // ============ Fee Withdrawal Tests ============

    function testWithdrawFees() public {
        // Collect some fees
        vm.prank(admin);
        stableCoin.setMintFee(100); // 1%

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 10000e6);
        stableCoin.mint(1000e6); // Fee = 10 USDT
        vm.stopPrank();

        uint256 feesCollected = stableCoin.totalFeesToBeCollected();
        assertEq(feesCollected, 10e6);

        // Withdraw fees
        vm.prank(admin);
        stableCoin.withdrawFees(feeRecipient, feesCollected);

        // Check recipient balance
        assertEq(usdt.balanceOf(feeRecipient), feesCollected);

        // Check fees tracking updated
        assertEq(stableCoin.totalFeesToBeCollected(), 0);
    }

    function testWithdrawPartialFees() public {
        // Collect fees
        vm.prank(admin);
        stableCoin.setMintFee(100); // 1%

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 10000e6);
        stableCoin.mint(1000e6); // Fee = 10 USDT
        vm.stopPrank();

        // Withdraw half the fees
        uint256 withdrawAmount = 5e6;
        vm.prank(admin);
        stableCoin.withdrawFees(feeRecipient, withdrawAmount);

        assertEq(usdt.balanceOf(feeRecipient), withdrawAmount);
        assertEq(stableCoin.totalFeesToBeCollected(), 5e6);
    }

    function testCannotWithdrawMoreThanCollected() public {
        vm.prank(admin);
        vm.expectRevert();
        stableCoin.withdrawFees(feeRecipient, 1e6);
    }

    function testOnlyAdminCanWithdrawFees() public {
        // Collect some fees first
        vm.prank(admin);
        stableCoin.setMintFee(100);

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);
        vm.stopPrank();

        // Non-admin tries to withdraw
        vm.prank(user1);
        vm.expectRevert();
        stableCoin.withdrawFees(user1, 1e6);
    }

    // ============ Integration Tests ============

    function testFullCycleWithFees() public {
        // Set fees
        vm.prank(admin);
        stableCoin.setMintFee(50); // 0.5%
        vm.prank(admin);
        stableCoin.setRedeemFee(50); // 0.5%

        // User1 deposits 1000 USDT
        uint256 depositAmount = 1000e6;
        uint256 mintFee = (depositAmount * 50) / 10000; // 5 USDT

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        uint256 ilsReceived = stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Check fees from mint
        assertEq(stableCoin.totalFeesToBeCollected(), mintFee);

        // User redeems all tokens
        uint256 usdtBeforeFee = converter.getExchangeRate(false, ilsReceived);
        uint256 redeemFee = (usdtBeforeFee * 50) / 10000;

        vm.prank(user1);
        uint256 usdtReceived = stableCoin.redeem(ilsReceived);

        // Total fees should be mint fee + redeem fee
        uint256 totalFees = mintFee + redeemFee;
        assertEq(stableCoin.totalFeesToBeCollected(), totalFees);

        // Withdraw all fees
        vm.prank(admin);
        stableCoin.withdrawFees(feeRecipient, totalFees);

        assertEq(usdt.balanceOf(feeRecipient), totalFees);
        assertEq(stableCoin.totalFeesToBeCollected(), 0);
    }

    function testCollateralRatioWithFees() public {
        // Set 1% mint fee
        vm.prank(admin);
        stableCoin.setMintFee(100);

        // Mint tokens
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdt.approve(address(stableCoin), depositAmount);
        stableCoin.mint(depositAmount);
        vm.stopPrank();

        // Get info
        (
            ,
            uint256 totalSupply_,
            uint256 totalCollateral,
            uint256 netCollateral,
            uint256 feesCollected,
            ,
            ,
            
        ) = stableCoin.getInfo();

        uint256 requiredCollateral = converter.getExchangeRate(false, totalSupply_);
        uint256 collateralRatio = (netCollateral * 10000) / requiredCollateral;

        // Verify accounting
        assertEq(totalCollateral, depositAmount); // Includes fees
        assertEq(feesCollected, 10e6); // 1% of 1000
        assertEq(netCollateral, depositAmount - feesCollected); // Excludes fees

        // Collateral ratio should be ~100% (based on net collateral)
        assertApproxEqRel(collateralRatio, 10000, 0.01e18);
    }

    // ============ Event Tests ============

    function testMintFeeUpdateEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit LocalCurrencyToken.MintFeeUpdated(0, 100);
        stableCoin.setMintFee(100);
    }

    function testRedeemFeeUpdateEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit LocalCurrencyToken.RedeemFeeUpdated(0, 50);
        stableCoin.setRedeemFee(50);
    }

    function testFeeWithdrawalEvent() public {
        // Collect fees
        vm.prank(admin);
        stableCoin.setMintFee(100);

        vm.startPrank(user1);
        usdt.approve(address(stableCoin), 1000e6);
        stableCoin.mint(1000e6);
        vm.stopPrank();

        // Withdraw fees
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit LocalCurrencyToken.FeesWithdrawn(feeRecipient, 10e6);
        stableCoin.withdrawFees(feeRecipient, 10e6);
    }
}
