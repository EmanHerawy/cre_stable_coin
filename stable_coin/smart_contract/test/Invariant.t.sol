// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StableCoin.sol";
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
 * @title StableCoinHandler
 * @notice Handler contract for stateful fuzzing
 * @dev Performs random sequences of operations while tracking state
 */
contract StableCoinHandler is Test {
    LocalCurrencyToken public stableCoin;
    MockUSDT public usdt;
    address public admin;

    // Actors
    address[] public actors;
    address internal currentActor;

    // Tracking variables
    uint256 public ghost_depositSum;
    uint256 public ghost_redeemSum;
    uint256 public ghost_feesCollectedSum;
    uint256 public ghost_mintCount;
    uint256 public ghost_redeemCount;

    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(LocalCurrencyToken _stableCoin, MockUSDT _usdt, address _admin) {
        stableCoin = _stableCoin;
        usdt = _usdt;
        admin = _admin;

        // Create actors
        for (uint i = 0; i < 10; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
            actors.push(actor);
            // Fund actors
            usdt.mint(actor, 1_000_000_000e6); // 1B USDT each
        }
    }

    // ============ Handler Functions ============

    function mint(uint256 actorSeed, uint256 amount) external useActor(actorSeed) countCall("mint") {
        amount = bound(amount, stableCoin.minDeposit(), 10_000_000e6); // 1 to 10M USDT

        usdt.approve(address(stableCoin), amount);

        try stableCoin.mint(amount) returns (uint256 tokens) {
            ghost_depositSum += amount;
            ghost_mintCount++;

            // Track fees
            uint256 fee = (amount * stableCoin.mintFeeBps()) / 10000;
            ghost_feesCollectedSum += fee;
        } catch {
            // Mint failed, that's ok
        }
    }

    function redeem(uint256 actorSeed, uint256 tokenPercent) external useActor(actorSeed) countCall("redeem") {
        uint256 balance = stableCoin.balanceOf(currentActor);
        if (balance == 0) return;

        tokenPercent = bound(tokenPercent, 1, 100);
        uint256 redeemAmount = (balance * tokenPercent) / 100;

        if (redeemAmount == 0) return;

        uint256 previewUsdt = stableCoin.previewRedeem(redeemAmount);
        if (previewUsdt < stableCoin.minWithdrawal()) return;

        try stableCoin.redeem(redeemAmount) returns (uint256 usdtAmount) {
            ghost_redeemSum += usdtAmount;
            ghost_redeemCount++;

            // Track fees
            uint256 usdtBeforeFee = stableCoin.previewRedeem(redeemAmount);
            uint256 fee = (usdtBeforeFee * stableCoin.redeemFeeBps()) / 10000;
            ghost_feesCollectedSum += fee;
        } catch {
            // Redeem failed, that's ok
        }
    }

    function setMintFee(uint256 feeBps) external countCall("setMintFee") {
        feeBps = bound(feeBps, 0, 1000);

        vm.prank(admin);
        try stableCoin.setMintFee(feeBps) {
            // Success
        } catch {
            // Failed, that's ok
        }
    }

    function setRedeemFee(uint256 feeBps) external countCall("setRedeemFee") {
        feeBps = bound(feeBps, 0, 1000);

        vm.prank(admin);
        try stableCoin.setRedeemFee(feeBps) {
            // Success
        } catch {
            // Failed, that's ok
        }
    }

    function withdrawFees(uint256 withdrawPercent) external countCall("withdrawFees") {
        uint256 feesAvailable = stableCoin.totalFeesCollected();
        if (feesAvailable == 0) return;

        withdrawPercent = bound(withdrawPercent, 1, 100);
        uint256 withdrawAmount = (feesAvailable * withdrawPercent) / 100;

        vm.prank(admin);
        try stableCoin.withdrawFees(admin, withdrawAmount) {
            // Success
        } catch {
            // Failed, that's ok
        }
    }

    // ============ View Functions for Invariants ============

    function actorCount() public view returns (uint256) {
        return actors.length;
    }

    function getTotalValueInSystem() public view returns (uint256) {
        return stableCoin.getTotalCollateral();
    }

    function getNetCollateralValue() public view returns (uint256) {
        return stableCoin.getNetCollateral();
    }

    function getTotalSupply() public view returns (uint256) {
        return stableCoin.totalSupply();
    }

    function getRequiredCollateral() public view returns (uint256) {
        uint256 supply = stableCoin.totalSupply();
        if (supply == 0) return 0;
        return stableCoin.previewRedeem(supply);
    }
}

/**
 * @title InvariantTest
 * @notice Stateful fuzz tests that maintain critical system invariants
 */
contract InvariantTest is Test {
    LocalCurrencyToken public stableCoin;
    MockUSDT public usdt;
    StableCoinHandler public handler;

    address public admin = address(1);

    uint256 constant INITIAL_RATE = 3_223_000; // 3.223 ILS per USDT

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

        handler = new StableCoinHandler(stableCoin, usdt, admin);

        // Target handler for invariant testing
        targetContract(address(handler));

        // Configure selectors
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = StableCoinHandler.mint.selector;
        selectors[1] = StableCoinHandler.redeem.selector;
        selectors[2] = StableCoinHandler.setMintFee.selector;
        selectors[3] = StableCoinHandler.setRedeemFee.selector;
        selectors[4] = StableCoinHandler.withdrawFees.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }

    // ============ Critical Invariants ============

    /// @notice INVARIANT 1: Net collateral must always be sufficient to back all tokens
    function invariant_CollateralBacksAllTokens() public view {
        uint256 totalSupply = handler.getTotalSupply();

        if (totalSupply > 0) {
            uint256 requiredCollateral = handler.getRequiredCollateral();
            uint256 netCollateral = handler.getNetCollateralValue();

            assertGe(
                netCollateral,
                requiredCollateral,
                "INVARIANT VIOLATED: Insufficient collateral to back tokens"
            );
        }
    }

    /// @notice INVARIANT 2: Total collateral = Net collateral + Fees collected
    function invariant_CollateralAccounting() public view {
        uint256 totalCollateral = stableCoin.getTotalCollateral();
        uint256 netCollateral = stableCoin.getNetCollateral();
        uint256 feesCollected = stableCoin.totalFeesCollected();

        assertEq(
            totalCollateral,
            netCollateral + feesCollected,
            "INVARIANT VIOLATED: Collateral accounting mismatch"
        );
    }

    /// @notice INVARIANT 3: Fees collected should never exceed total collateral
    function invariant_FeesWithinCollateral() public view {
        uint256 totalCollateral = stableCoin.getTotalCollateral();
        uint256 feesCollected = stableCoin.totalFeesCollected();

        assertLe(
            feesCollected,
            totalCollateral,
            "INVARIANT VIOLATED: Fees exceed total collateral"
        );
    }

    /// @notice INVARIANT 4: Net collateral should never be negative (using uint, but check underflow)
    function invariant_NetCollateralNonNegative() public view {
        uint256 totalCollateral = stableCoin.getTotalCollateral();
        uint256 feesCollected = stableCoin.totalFeesCollected();

        // This should never underflow if accounting is correct
        uint256 netCollateral = stableCoin.getNetCollateral();

        if (totalCollateral >= feesCollected) {
            assertEq(
                netCollateral,
                totalCollateral - feesCollected,
                "INVARIANT VIOLATED: Net collateral calculation incorrect"
            );
        } else {
            assertEq(netCollateral, 0, "INVARIANT VIOLATED: Net collateral should be 0 when fees > collateral");
        }
    }

    /// @notice INVARIANT 5: Total supply matches sum of all user balances
    function invariant_TotalSupplyMatchesBalances() public view {
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 sumOfBalances = 0;

        // Sum all actor balances
        uint256 actorCount = handler.actorCount();
        for (uint i = 0; i < actorCount; i++) {
            sumOfBalances += stableCoin.balanceOf(handler.actors(i));
        }

        assertEq(
            totalSupply,
            sumOfBalances,
            "INVARIANT VIOLATED: Total supply doesn't match sum of balances"
        );
    }

    /// @notice INVARIANT 6: Solvency - Contract can always pay out all users (excluding fees)
    function invariant_Solvency() public view {
        uint256 totalSupply = handler.getTotalSupply();

        if (totalSupply > 0) {
            uint256 requiredToPayAll = handler.getRequiredCollateral();
            uint256 netCollateral = handler.getNetCollateralValue();

            // Net collateral should be able to cover all redemptions
            assertGe(
                netCollateral,
                requiredToPayAll,
                "INVARIANT VIOLATED: Contract is insolvent"
            );
        }
    }

    /// @notice INVARIANT 7: Exchange rate remains constant (no oracle in test setup)
    function invariant_ExchangeRateStable() public view {
        uint256 currentRate = stableCoin.getExchangeRate();
        assertEq(
            currentRate,
            INITIAL_RATE,
            "INVARIANT VIOLATED: Exchange rate changed unexpectedly"
        );
    }

    /// @notice INVARIANT 8: Mint and redeem fees within bounds
    function invariant_FeesWithinBounds() public view {
        uint256 mintFee = stableCoin.mintFeeBps();
        uint256 redeemFee = stableCoin.redeemFeeBps();
        uint256 maxFee = stableCoin.MAX_FEE_BPS();

        assertLe(mintFee, maxFee, "INVARIANT VIOLATED: Mint fee exceeds maximum");
        assertLe(redeemFee, maxFee, "INVARIANT VIOLATED: Redeem fee exceeds maximum");
    }

    /// @notice INVARIANT 9: Collateral ratio should be approximately 100% (allowing for fees)
    function invariant_CollateralRatio() public view {
        uint256 totalSupply = handler.getTotalSupply();

        if (totalSupply > 0) {
            uint256 requiredCollateral = handler.getRequiredCollateral();
            uint256 netCollateral = handler.getNetCollateralValue();

            // Calculate ratio in basis points
            uint256 ratio = (netCollateral * 10000) / requiredCollateral;

            // Should be very close to 100% (10000 bps)
            // Allow small rounding errors (within 1%)
            assertApproxEqRel(
                ratio,
                10000,
                0.01e18,
                "INVARIANT VIOLATED: Collateral ratio significantly off 100%"
            );
        }
    }

    /// @notice INVARIANT 10: No user can have more tokens than total supply
    function invariant_UserBalanceWithinSupply() public view {
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 actorCount = handler.actorCount();

        for (uint i = 0; i < actorCount; i++) {
            uint256 balance = stableCoin.balanceOf(handler.actors(i));
            assertLe(
                balance,
                totalSupply,
                "INVARIANT VIOLATED: User balance exceeds total supply"
            );
        }
    }

    // ============ Statistics and Logging ============

    function invariant_callSummary() public view {
        console.log("\n=== Call Summary ===");
        console.log("mint calls:", handler.calls("mint"));
        console.log("redeem calls:", handler.calls("redeem"));
        console.log("setMintFee calls:", handler.calls("setMintFee"));
        console.log("setRedeemFee calls:", handler.calls("setRedeemFee"));
        console.log("withdrawFees calls:", handler.calls("withdrawFees"));

        console.log("\n=== Ghost Variables ===");
        console.log("Total deposited:", handler.ghost_depositSum());
        console.log("Total redeemed:", handler.ghost_redeemSum());
        console.log("Total fees collected:", handler.ghost_feesCollectedSum());
        console.log("Mint count:", handler.ghost_mintCount());
        console.log("Redeem count:", handler.ghost_redeemCount());

        console.log("\n=== Contract State ===");
        console.log("Total supply:", stableCoin.totalSupply());
        console.log("Total collateral:", stableCoin.getTotalCollateral());
        console.log("Net collateral:", stableCoin.getNetCollateral());
        console.log("Fees collected:", stableCoin.totalFeesCollected());
        console.log("Mint fee (bps):", stableCoin.mintFeeBps());
        console.log("Redeem fee (bps):", stableCoin.redeemFeeBps());
    }
}
