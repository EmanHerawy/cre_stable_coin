// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/Pausable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "./Converter.sol";

/**
 * @title LocalCurrencyToken
 * @dev Digital representation of local currency backed by USDT
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 * EXAMPLE WORKFLOW: Egyptian Pound (EGP) Digital Token
 * ═══════════════════════════════════════════════════════════════════════════════
 * ## 🔐 Design Decisions

 * ### 1. Manual Price Fallback

 * Decision: No deviation check in fallback path
 * Rationale: Prevents DoS when oracle fails
 * Trade-off: Requires admin to keep manual rate updated
 * Mitigation: Admin is trusted role, event logging for transparency
 
 * ### 2. 6-Decimal Rates

 * Decision: All rates use 6 decimals internally
 * Rationale: Matches USDT decimals, simplifies calculations
 * Trade-off: Rate precision limited to 6 decimals
 *Mitigation: Sufficient for currency rates (e.g., 50.123456 EGP/USDT)

* ### 3. Converter Separation

* Decision: Separate Converter contract for rate management
* Rationale: Modularity, upgradability, testability
* Trade-off: Additional deployment complexity
* Mitigation: Comprehensive deployment scripts and tests

* ## 📝 Known Limitations

* 1.  Admin is trusted to set accurate manual rates
* 2.  Assumes CRE oracle provides 6-decimal rates
* 3.  Assumes USDT has 6 decimals
* 4.  Small rounding errors (<0.1%) in conversions
 * ARCHITECTURE:
 * -------------
 * This contract delegates ALL rate management to the Converter contract:
 * - Oracle integration
 * - Manual rate updates
 * - Deviation protection
 * - Price staleness checks
 * 
 * MINTING (USDT → Local Currency):
 * --------------------------------
 * 1. User deposits 100 USDT (6 decimals)
 * 2. Converter provides rate: 1 USDT = 50 EGP
 * 3. Calculation: 100 USDT × 50 rate = 5,000 EGP
 * 4. User receives 5,000 EGP tokens (18 decimals)
 * 
 * REDEEMING (Local Currency → USDT):
 * ----------------------------------
 * 1. User redeems 5,000 EGP tokens
 * 2. Converter provides rate: 1 USDT = 50 EGP
 * 3. Calculation: 5,000 EGP ÷ 50 rate = 100 USDT
 * 4. User receives 100 USDT (6 decimals)
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 */

contract LocalCurrencyToken is ERC20, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Core Dependencies
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice USDT token (collateral)
    IERC20 public immutable usdt;

    /// @notice Converter contract - handles all rate logic
    Converter public converter;

    // ─────────────────────────────────────────────────────────────────────────
    // Transaction Limits
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Minimum deposit amount (in USDT, 6 decimals)
    uint256 public minDeposit;

    /// @notice Minimum withdrawal amount (in USDT, 6 decimals)
    uint256 public minWithdrawal;

    // ─────────────────────────────────────────────────────────────────────────
    // Fee Configuration
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Mint fee in basis points (e.g., 100 = 1%)
    uint256 public mintFeeBps;

    /// @notice Redeem fee in basis points (e.g., 100 = 1%)
    uint256 public redeemFeeBps;

    /// @notice Total fees collected (in USDT) - not yet withdrawn
    uint256 public totalFeesToBeCollected;

    /// @notice Maximum allowed fee (10% = 1000 bps)
    uint256 public constant MAX_FEE_BPS = 1000;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Transaction Events
    // ─────────────────────────────────────────────────────────────────────────

    event Minted(
        address indexed user, 
        uint256 usdtAmount, 
        uint256 localCurrencyAmount, 
        uint256 fee
    );
    
    event Redeemed(
        address indexed user, 
        uint256 localCurrencyAmount, 
        uint256 usdtAmount, 
        uint256 fee
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Configuration Events
    // ─────────────────────────────────────────────────────────────────────────

    event ConverterUpdated(address indexed oldConverter, address indexed newConverter);
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    event RedeemFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event MinDepositUpdated(uint256 oldMin, uint256 newMin);
    event MinWithdrawalUpdated(uint256 oldMin, uint256 newMin);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidAddress();
    error InvalidAmount();
    error DepositBelowMinimum(uint256 amount, uint256 minimum);
    error WithdrawalBelowMinimum(uint256 amount, uint256 minimum);
    error InsufficientCollateral(uint256 required, uint256 available);
    error InvalidMinimumAmount();
    error FeeTooHigh(uint256 fee, uint256 maxFee);
    error NoFeesToWithdraw();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the LocalCurrencyToken contract
     * @dev All rate management is delegated to the Converter contract
     * 
     * @param usdtAddress USDT token address
     * @param currencyName Name of local currency (e.g., "Egyptian Pound Digital")
     * @param currencySymbol Symbol (e.g., "EGPd")
     * @param converterAddress Converter contract address (handles all rate logic)
     * @param admin Admin address (receives all roles initially)
     */
    constructor(
        address usdtAddress,
        string memory currencyName,
        string memory currencySymbol,
        address converterAddress,
        address admin
    ) ERC20(currencyName, currencySymbol) {
        if (usdtAddress == address(0) || converterAddress == address(0) || admin == address(0)) {
            revert InvalidAddress();
        }

        usdt = IERC20(usdtAddress);
        converter = Converter(converterAddress);

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        // Set defaults
        minDeposit = 1e6; // 1 USDT
        minWithdrawal = 1e6; // 1 USDT equivalent
        mintFeeBps = 0; // 0% fee initially
        redeemFeeBps = 0; // 0% fee initially
        totalFeesToBeCollected = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MINT (DEPOSIT) FUNCTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ MINT - DEPOSIT USDT FOR LOCAL CURRENCY TOKENS                           │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     * @notice Deposit USDT and receive local currency tokens
     * @dev Uses Converter.getExchangeRate(true, amount) to calculate output
     * 
     * @param usdtAmount Amount of USDT to deposit (6 decimals, before fees)
     * @return localAmount Amount of local currency tokens received (18 decimals)
     * 
     * FLOW:
     * ─────
     * 1. Check minimum deposit requirement
     * 2. Calculate and deduct mint fee
     * 3. Get conversion rate from Converter (direction = true for mint)
     * 4. Transfer USDT from user
     * 5. Mint local currency tokens to user
     */
    function mint(uint256 usdtAmount) 
        external 
        whenNotPaused 
        nonReentrant 
        returns (uint256 localAmount) 
    {
        if (usdtAmount < minDeposit) {
            revert DepositBelowMinimum(usdtAmount, minDeposit);
        }

        // Calculate fee (in USDT)
        uint256 fee = (usdtAmount * mintFeeBps) / 10000;
        uint256 usdtAfterFee = usdtAmount - fee;

        uint256 balanceBefore = getTotalCollateral();

        // Get conversion from Converter: USDT -> Local Currency (direction = true)
        localAmount = converter.getExchangeRate(true, usdtAfterFee);

        if (localAmount == 0) revert InvalidAmount();

        // Transfer USDT from user to contract
        usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);
        uint256 balanceAfter = getTotalCollateral();

        if (balanceAfter < balanceBefore + usdtAmount) {
            revert InsufficientCollateral(balanceBefore + usdtAmount, balanceAfter);
        }

        // Track fees collected
        totalFeesToBeCollected += fee;

        // Mint local currency tokens to user
        _mint(msg.sender, localAmount);

        emit Minted(msg.sender, usdtAfterFee, localAmount, fee);

        return localAmount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REDEEM (BURN) FUNCTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ REDEEM - BURN LOCAL CURRENCY TOKENS FOR USDT                            │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     * @notice Redeem local currency tokens for USDT
     * @dev Uses Converter.getExchangeRate(false, amount) to calculate output
     * 
     * @param localAmount Amount of local currency tokens to redeem (18 decimals)
     * @return usdtAmountAfterFee Amount of USDT received (6 decimals, after fees)
     * 
     * FLOW:
     * ─────
     * 1. Validate amount and balance
     * 2. Get conversion rate from Converter (direction = false for redeem)
     * 3. Calculate and deduct redeem fee
     * 4. Check minimum withdrawal requirement
     * 5. Verify sufficient collateral
     * 6. Burn local currency tokens
     * 7. Transfer USDT to user
     */
    function redeem(uint256 localAmount) 
        external 
        whenNotPaused 
        nonReentrant 
        returns (uint256 usdtAmountAfterFee) 
    {
        if (localAmount == 0) revert InvalidAmount();
        if (localAmount > balanceOf(msg.sender)) revert InvalidAmount();

        // Get conversion from Converter: Local Currency -> USDT (direction = false)
        uint256 usdtAmount = converter.getExchangeRate(false, localAmount);

        // CRITICAL: Prevent precision loss - ensure non-zero input doesn't round to zero output
        if (usdtAmount == 0) revert InvalidAmount();

        // Calculate fee (in USDT)
        uint256 fee = (usdtAmount * redeemFeeBps) / 10000;
        usdtAmountAfterFee = usdtAmount - fee;

        if (usdtAmountAfterFee < minWithdrawal) {
            revert WithdrawalBelowMinimum(usdtAmountAfterFee, minWithdrawal);
        }

        // Check actual USDT balance is sufficient (including fees in vault)
        uint256 vaultBalance = getTotalCollateral();
        if (usdtAmount > vaultBalance) {
            revert InsufficientCollateral(usdtAmount, vaultBalance);
        }

        // Track fees collected
        totalFeesToBeCollected += fee;

        // Burn local currency tokens
        _burn(msg.sender, localAmount);

        // Transfer USDT to user (after fee)
        usdt.safeTransfer(msg.sender, usdtAmountAfterFee);

        emit Redeemed(msg.sender, localAmount, usdtAmountAfterFee, fee);

        return usdtAmountAfterFee;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update the Converter contract address
     * @dev Can only be called when contract is paused for safety
     * @param newConverter The new Converter contract address
     */
    function setConverter(address newConverter) external onlyRole(ADMIN_ROLE) whenPaused {
        if (newConverter == address(0)) revert InvalidAddress();
        
        address oldConverter = address(converter);
        
        // Check if it's the same address
        if (newConverter == oldConverter) revert InvalidAddress();
        
        converter = Converter(newConverter);
        
        emit ConverterUpdated(oldConverter, newConverter);
    }

    /**
     * @notice Set minimum deposit amount
     * @param newMin Minimum deposit amount in USDT (6 decimals, must be > 0)
     */
    function setMinDeposit(uint256 newMin) external onlyRole(ADMIN_ROLE) {
        if (newMin == 0) revert InvalidMinimumAmount();

        uint256 oldMin = minDeposit;
        minDeposit = newMin;

        emit MinDepositUpdated(oldMin, newMin);
    }

    /**
     * @notice Set minimum withdrawal amount
     * @param newMin Minimum withdrawal amount in USDT (6 decimals, must be > 0)
     */
    function setMinWithdrawal(uint256 newMin) external onlyRole(ADMIN_ROLE) {
        if (newMin == 0) revert InvalidMinimumAmount();

        uint256 oldMin = minWithdrawal;
        minWithdrawal = newMin;

        emit MinWithdrawalUpdated(oldMin, newMin);
    }

    /**
     * @notice Set mint fee in basis points
     * @param newFeeBps New fee (e.g., 100 = 1%, max 1000 = 10%)
     */
    function setMintFee(uint256 newFeeBps) external onlyRole(ADMIN_ROLE) {
        if (newFeeBps > MAX_FEE_BPS) {
            revert FeeTooHigh(newFeeBps, MAX_FEE_BPS);
        }

        uint256 oldFee = mintFeeBps;
        mintFeeBps = newFeeBps;

        emit MintFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @notice Set redeem fee in basis points
     * @param newFeeBps New fee (e.g., 100 = 1%, max 1000 = 10%)
     */
    function setRedeemFee(uint256 newFeeBps) external onlyRole(ADMIN_ROLE) {
        if (newFeeBps > MAX_FEE_BPS) {
            revert FeeTooHigh(newFeeBps, MAX_FEE_BPS);
        }

        uint256 oldFee = redeemFeeBps;
        redeemFeeBps = newFeeBps;

        emit RedeemFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ WITHDRAW COLLECTED FEES                                                 │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     * @notice Withdraw collected fees (in USDT)
     * @dev Used to pay for Chainlink CRE costs and protocol maintenance
     * 
     * ⚠️  CRITICAL SECURITY:
     * ─────────────────────
     * Ensures withdrawal doesn't compromise collateralization
     * Must maintain sufficient collateral for all potential redemptions
     * 
     * @param recipient Address to receive the fees
     * @param amount Amount of fees to withdraw (must not exceed totalFeesToBeCollected)
     */
    function withdrawFees(address recipient, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
        nonReentrant 
    {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (totalFeesToBeCollected == 0) revert NoFeesToWithdraw();
        if (amount > totalFeesToBeCollected) {
            revert InsufficientCollateral(amount, totalFeesToBeCollected);
        }

   uint256 requiredCollateral = converter.getExchangeRate(false, totalSupply());
        if (getNetCollateral() < requiredCollateral) {
            revert InsufficientCollateral(requiredCollateral, getNetCollateral());
        }


        // Deduct from tracked fees
        totalFeesToBeCollected -= amount;

        // Transfer USDT fees to recipient
        usdt.safeTransfer(recipient, amount);

        emit FeesWithdrawn(recipient, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause all contract operations
     * @dev Only PAUSER_ROLE can call this function
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract operations
     * @dev Only PAUSER_ROLE can call this function
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Collateral Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get the total USDT balance in the contract (including fees)
     * @return Total USDT balance (6 decimals)
     */
    function getTotalCollateral() public view returns (uint256) {
        return usdt.balanceOf(address(this));
    }

    /**
     * @notice Get the actual collateral backing tokens (excluding fees)
     * @return Net collateral amount (6 decimals)
     */
    function getNetCollateral() public view returns (uint256) {
        uint256 totalBalance = getTotalCollateral();
        // Fees are part of the balance but not backing tokens
        return totalBalance > totalFeesToBeCollected 
            ? totalBalance - totalFeesToBeCollected 
            : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Preview Functions
    // ─────────────────────────────────────────────────────────────────────────



    // ─────────────────────────────────────────────────────────────────────────
    // Information Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get comprehensive contract information
     * @return currentRate Current exchange rate from Converter (6 decimals)
     * @return totalSupply_ Total supply of local currency tokens (18 decimals)
     * @return collateral Total USDT collateral including fees (6 decimals)
     * @return netCollateral USDT collateral excluding fees (6 decimals)
     * @return feesCollected Total fees collected in USDT (6 decimals)
     * @return mintFee Mint fee in basis points
     * @return redeemFee Redeem fee in basis points
     * @return converterAddress Address of the Converter contract
     */
    function getInfo() external view returns (
        uint256 currentRate,
        uint256 totalSupply_,
        uint256 collateral,
        uint256 netCollateral,
        uint256 feesCollected,
        uint256 mintFee,
        uint256 redeemFee,
        address converterAddress
    ) {
        currentRate = converter.getExchangeRateView();
        totalSupply_ = totalSupply();
        collateral = getTotalCollateral();
        netCollateral = getNetCollateral();


        feesCollected = totalFeesToBeCollected;
        mintFee = mintFeeBps;
        redeemFee = redeemFeeBps;
        converterAddress = address(converter);
    }


}
