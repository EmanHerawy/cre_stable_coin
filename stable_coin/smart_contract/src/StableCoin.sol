// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/Pausable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "./PriceFeedReceiver.sol";

/**
 * @title LocalCurrencyToken
 * @dev Digital representation of local currency backed by USDT
 * 
 * Example: Egyptian Pound (EGP) Digital Token
 * 
 * How it works:
 * 1. User deposits 100 USDT
 * 2. Oracle provides rate: 1 USDT = 50 EGP
 * 3. User receives 5000 EGP tokens
 * 4. User can redeem anytime at current rate
 * 
 * Rate updates via Chainlink oracle or admin
 */



contract LocalCurrencyToken is ERC20, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");

    // ============ State Variables ============

    /// @notice USDT token (collateral)
    IERC20 public immutable usdt;

    /// @notice Chainlink CRE price feed receiver (optional - can use manual rate)
    PriceFeedReceiver public priceFeedReceiver;

    /// @notice Manual exchange rate (used if oracle disabled)
    /// @dev Stored with 6 decimals. Example: 50e6 = 50 local currency per 1 USDT
    uint256 public manualRate;

    /// @notice Whether to use Chainlink CRE oracle (true) or manual rate (false)
    bool public useOracle;

    /// @notice Minimum deposit/withdrawal amounts
    uint256 public minDeposit;
    uint256 public minWithdrawal;

    /// @notice Maximum price age for oracle (seconds)
    uint256 public maxPriceAge;

    /// @notice Last manual rate update timestamp
    uint256 public lastManualRateUpdate;

    /// @notice Mint fee in basis points (e.g., 100 = 1%)
    uint256 public mintFeeBps;

    /// @notice Redeem fee in basis points (e.g., 100 = 1%)
    uint256 public redeemFeeBps;

    /// @notice Total fees collected (in USDT)
    uint256 public totalFeesCollected;

    /// @notice Maximum allowed fee (10% = 1000 bps)
    uint256 public constant MAX_FEE_BPS = 1000;

    // ============ Events ============

    event Minted(address indexed user, uint256 usdtAmount, uint256 localCurrencyAmount, uint256 fee);
    event Redeemed(address indexed user, uint256 localCurrencyAmount, uint256 usdtAmount, uint256 fee);
    event RateUpdated(uint256 oldRate, uint256 newRate, bool isOracle);
    event OracleToggled(bool useOracle);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    event RedeemFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed recipient, uint256 amount);

    // ============ Errors ============

    error InvalidAddress();
    error InvalidAmount();
    error DepositBelowMinimum(uint256 amount, uint256 minimum);
    error WithdrawalBelowMinimum(uint256 amount, uint256 minimum);
    error InsufficientCollateral(uint256 required, uint256 available);
    error StalePriceData(uint256 updatedAt, uint256 currentTime);
    error InvalidPriceData();
    error InvalidRate();
    error InvalidPriceAge();
    error InvalidMinimumAmount();
    error FeeTooHigh(uint256 fee, uint256 maxFee);
    error NoFeesToWithdraw();

    // ============ Constructor ============

    /**
     * @param usdtAddress USDT token address
     * @param currencyName Name of local currency (e.g., "Egyptian Pound Digital")
     * @param currencySymbol Symbol (e.g., "EGPd")
     * @param initialRate Initial exchange rate (6 decimals, e.g., 50e6 = 50 EGP per USDT)
     * @param admin Admin address
     * @param priceFeedReceiverAddress PriceFeedReceiver contract address (can be address(0) to use manual rate only)
     */
    constructor(
        address usdtAddress,
        string memory currencyName,
        string memory currencySymbol,
        uint256 initialRate,
        address admin,
        address priceFeedReceiverAddress
    ) ERC20(currencyName, currencySymbol) {
        if (usdtAddress == address(0) || admin == address(0)) revert InvalidAddress();
        if (initialRate == 0) revert InvalidRate();

        usdt = IERC20(usdtAddress);
        manualRate = initialRate;

        // Setup oracle (optional)
        if (priceFeedReceiverAddress != address(0)) {
            priceFeedReceiver = PriceFeedReceiver(priceFeedReceiverAddress);
            useOracle = true;
        } else {
            useOracle = false; // Start with manual rate only
        }

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(RATE_UPDATER_ROLE, admin);

        // Set defaults
        minDeposit = 1e6; // 1 USDT
        minWithdrawal = 1e6; // 1 USDT equivalent
        maxPriceAge = 3600; // 1 hour
        mintFeeBps = 0; // 0% fee initially
        redeemFeeBps = 0; // 0% fee initially
        totalFeesCollected = 0;
    }

    // ============ Rate Functions ============

    /**
     * @dev Get current exchange rate (local currency per 1 USDT)
     * @return rate Exchange rate with 6 decimals
     */
    function getExchangeRate() public view returns (uint256 rate) {
        if (useOracle) {
            rate = _getOracleRate();
        } else {
            rate = manualRate;
        }
        return rate;
    }

    /**
     * @dev Get the last price update timestamp
     * @return timestamp The timestamp of the last price update
     * @dev Returns oracle timestamp if using oracle, otherwise manual rate timestamp
     */
    function getLastPriceUpdate() public view returns (uint256 timestamp) {
        if (useOracle && address(priceFeedReceiver) != address(0)) {
            try priceFeedReceiver.getPrice() returns (uint224, uint32 priceTimestamp) {
                return uint256(priceTimestamp);
            } catch {
                return lastManualRateUpdate;
            }
        }
        return lastManualRateUpdate;
    }

    /**
     * @dev Check if price data is stale
     * @return isStale True if price is older than maxPriceAge
     */
    function isPriceStale() public view returns (bool isStale) {
        uint256 lastUpdate = getLastPriceUpdate();
        if (lastUpdate == 0) return true;
        return (block.timestamp - lastUpdate) > maxPriceAge;
    }

    /**
     * @dev Get rate from Chainlink CRE price feed receiver
     * Falls back to manual rate if oracle data is stale or unavailable
     */
    function _getOracleRate() internal view returns (uint256) {
        if (address(priceFeedReceiver) == address(0)) {
            // Oracle not configured, use manual rate
            return manualRate;
        }

        try priceFeedReceiver.getPrice() returns (uint224 price, uint32 timestamp) {
            // Check staleness - if stale, fallback to manual rate
            if (block.timestamp - timestamp > maxPriceAge) {
                // Data is stale, use manual rate as fallback
                return manualRate;
            }

            // Validate price data
            if (price == 0) {
                // Invalid price, use manual rate as fallback
                return manualRate;
            }

            // Price from PriceFeedReceiver has 8 decimals (Chainlink standard)
            // USDT has 6 decimals
            // Convert to 6 decimals to match USDT decimals for internal use
            uint256 rate = uint256(price) / 100; // 8 decimals -> 6 decimals (USDT decimals)

            return rate;
        } catch {
            // Error fetching price, fallback to manual rate
            return manualRate;
        }
    }

    // ============ Preview Functions ============

    /**
     * @dev Preview how many local currency tokens you'll receive for USDT deposit
     * @param usdtAmount Amount of USDT to deposit
     * @return localAmount Amount of local currency tokens
     */
    function previewDeposit(uint256 usdtAmount) public view returns (uint256 localAmount) {
        uint256 rate = getExchangeRate();
        // localAmount = usdtAmount * rate
        // Both have 6 decimals, result should have token decimals (18)
        localAmount = (usdtAmount * rate * 1e18) / 1e12;
        return localAmount;
    }

    /**
     * @dev Preview how much USDT you'll receive for local currency redemption
     * @param localAmount Amount of local currency tokens to redeem
     * @return usdtAmount Amount of USDT
     */
    function previewRedeem(uint256 localAmount) public view returns (uint256 usdtAmount) {
        uint256 rate = getExchangeRate();
        // usdtAmount = localAmount / rate
        // localAmount has 18 decimals, rate has 6, result should have 6
        usdtAmount = (localAmount * 1e12) / (rate * 1e18);
        return usdtAmount;
    }

    // ============ Mint (Deposit) Function ============

    /**
     * @dev Deposit USDT and receive local currency tokens
     * @param usdtAmount Amount of USDT to deposit (before fees)
     * @return localAmount Amount of local currency tokens received
     */
    function mint(uint256 usdtAmount) external whenNotPaused nonReentrant returns (uint256 localAmount) {

        if (usdtAmount < minDeposit) {
            revert DepositBelowMinimum(usdtAmount, minDeposit);
        }

        // Calculate fee (in USDT)
        uint256 fee = (usdtAmount * mintFeeBps) / 10000;
        uint256 usdtAfterFee = usdtAmount - fee;

        uint256 balanceBefore = getTotalCollateral();

        // Calculate local currency amount based on USDT after fee
        localAmount = previewDeposit(usdtAfterFee);

        if (localAmount == 0) revert InvalidAmount();

        // Transfer USDT from user to contract
        usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);
        uint256 balanceAfter = getTotalCollateral();

        if (balanceAfter < balanceBefore + usdtAmount) {
            revert InsufficientCollateral(balanceBefore + usdtAmount, balanceAfter);
        }

        // Track fees collected
        totalFeesCollected += fee;

        // Mint local currency tokens to user
        _mint(msg.sender, localAmount);

        emit Minted(msg.sender, usdtAfterFee, localAmount, fee);

        return localAmount;
    }

    // ============ Burn (Redeem) Function ============

    /**
     * @dev Redeem local currency tokens for USDT
     * @param localAmount Amount of local currency tokens to redeem
     * @return usdtAmountAfterFee Amount of USDT received (after fees)
     */
    function redeem(uint256 localAmount) external whenNotPaused nonReentrant returns (uint256 usdtAmountAfterFee) {
        if (localAmount == 0) revert InvalidAmount();
        if (localAmount > balanceOf(msg.sender)) revert InvalidAmount();

        // Calculate USDT amount (before fee)
        uint256 usdtAmount = previewRedeem(localAmount);

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
        totalFeesCollected += fee;

        // Burn local currency tokens
        _burn(msg.sender, localAmount);

        // Transfer USDT to user (after fee)
        usdt.safeTransfer(msg.sender, usdtAmountAfterFee);

        emit Redeemed(msg.sender, localAmount, usdtAmountAfterFee, fee);

        return usdtAmountAfterFee;
    }

    // ============ Admin Functions ============

    /**
     * @dev Update manual exchange rate
     * @notice Can only be called when contract is paused for safety
     * @param newRate New rate (6 decimals)
     */
    function updateManualRate(uint256 newRate) external onlyRole(RATE_UPDATER_ROLE) whenPaused {
        if (newRate == 0) revert InvalidRate();

        uint256 oldRate = manualRate;
        manualRate = newRate;
        lastManualRateUpdate = block.timestamp;

        emit RateUpdated(oldRate, newRate, false);
    }

    /**
     * @dev Update the PriceFeedReceiver address
     * @notice Can only be called when contract is paused for safety
     * @param newPriceFeedReceiver The new PriceFeedReceiver contract address
     */
    function setPriceFeedReceiver(address newPriceFeedReceiver) external onlyRole(ADMIN_ROLE) whenPaused {
        if (newPriceFeedReceiver == address(0)) {
            revert InvalidAddress();
        }

        address oldFeed = address(priceFeedReceiver);

        // Check if it's the same address
        if (newPriceFeedReceiver == oldFeed) {
            revert InvalidAddress(); // Already set to this address
        }

        priceFeedReceiver = PriceFeedReceiver(newPriceFeedReceiver);

        emit PriceFeedUpdated(oldFeed, newPriceFeedReceiver);
    }

    /**
     * @dev Toggle between oracle and manual rate
     * @notice Can only be called when contract is paused for safety
     * @notice Flips the current useOracle state (true -> false, false -> true)
     */
    function toggleUseOracle() external onlyRole(ADMIN_ROLE) whenPaused {
        useOracle = !useOracle;
        emit OracleToggled(useOracle);
    }

    /**
     * @dev Set max price age for oracle
     * @param newAge Maximum age in seconds (must be greater than 0)
     */
    function setMaxPriceAge(uint256 newAge) external onlyRole(ADMIN_ROLE) {
        if (newAge == 0) revert InvalidPriceAge();
        maxPriceAge = newAge;
    }

    /**
     * @dev Set minimum deposit
     * @param newMin Minimum deposit amount (must be greater than 0)
     */
    function setMinDeposit(uint256 newMin) external onlyRole(ADMIN_ROLE) {
        if (newMin == 0) revert InvalidMinimumAmount();
        minDeposit = newMin;
    }

    /**
     * @dev Set minimum withdrawal
     * @param newMin Minimum withdrawal amount (must be greater than 0)
     */
    function setMinWithdrawal(uint256 newMin) external onlyRole(ADMIN_ROLE) {
        if (newMin == 0) revert InvalidMinimumAmount();
        minWithdrawal = newMin;
    }

    /**
     * @dev Set mint fee in basis points
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
     * @dev Set redeem fee in basis points
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
     * @dev Withdraw collected fees (in USDT)
     * @param recipient Address to receive the fees
     * @param amount Amount of fees to withdraw (must not exceed totalFeesCollected)
     * @notice Used to pay for Chainlink CRE costs and protocol maintenance
     */
    function withdrawFees(address recipient, uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (totalFeesCollected == 0) revert NoFeesToWithdraw();
        if (amount > totalFeesCollected) {
            revert InsufficientCollateral(amount, totalFeesCollected);
        }

        // Deduct from tracked fees
        totalFeesCollected -= amount;

        // Transfer USDT fees to recipient
        usdt.safeTransfer(recipient, amount);

        emit FeesWithdrawn(recipient, amount);
    }

    // ============ Emergency Functions ============

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }


    // ============ View Functions ============

    /**
     * @dev Get the total USDT balance in the contract (including fees)
     * @return Total USDT balance
     */
    function getTotalCollateral() public view returns (uint256) {
        return usdt.balanceOf(address(this));
    }

    /**
     * @dev Get the actual collateral backing tokens (excluding fees)
     * @return Net collateral amount
     */
    function getNetCollateral() public view returns (uint256) {
        uint256 totalBalance = getTotalCollateral();
        // Fees are part of the balance but not backing tokens
        return totalBalance > totalFeesCollected ? totalBalance - totalFeesCollected : 0;
    }

    /**
     * @dev Get contract info
     */
    function getInfo() external view returns (
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
    ) {
        currentRate = getExchangeRate();
        totalSupply_ = totalSupply();
        collateral = getTotalCollateral();
        netCollateral = getNetCollateral();

        // Collateral ratio: should always be ~100% (using net collateral)
        if (totalSupply_ > 0) {
            uint256 requiredCollateral = previewRedeem(totalSupply_);
            collateralRatio = (netCollateral * 10000) / requiredCollateral; // Basis points
        } else {
            collateralRatio = 10000; // 100%
        }

        usingOracle = useOracle;
        lastUpdate = getLastPriceUpdate();
        priceIsStale = isPriceStale();
        feesCollected = totalFeesCollected;
        mintFee = mintFeeBps;
        redeemFee = redeemFeeBps;
    }
}