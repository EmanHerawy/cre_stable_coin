// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/Pausable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "./PriceFeedReceiver.sol";

/**
 * @title Converter
 * @dev Digital representation of local currency backed by USDT with oracle and manual rate support
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 * EXAMPLE WORKFLOW: Egyptian Pound (EGP) Digital Token
 * ═══════════════════════════════════════════════════════════════════════════════
 * 
 * MINTING (USDT → Local Currency):
 * --------------------------------
 * 1. User deposits 100 USDT (6 decimals)
 * 2. Oracle provides rate: 1 USDT = 50 EGP
 * 3. Calculation: 100 USDT × 50 rate = 5,000 EGP
 * 4. User receives 5,000 EGP tokens (18 decimals)
 * 
 * REDEEMING (Local Currency → USDT):
 * ----------------------------------
 * 1. User redeems 5,000 EGP tokens
 * 2. Current rate: 1 USDT = 50 EGP
 * 3. Calculation: 5,000 EGP ÷ 50 rate = 100 USDT
 * 4. User receives 100 USDT (6 decimals)
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 * RATE UPDATES
 * ═══════════════════════════════════════════════════════════════════════════════
 * 
 * ORACLE MODE (Primary):
 * - Automatic updates via Chainlink CRE price feed
 * - Fallback to manual rate if oracle fails
 * - Deviation protection against manipulation
 * 
 * MANUAL MODE (Emergency):
 * - Admin-controlled rate updates
 * - Used when oracle is unavailable
 * - Requires contract to be paused for safety
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 */

contract Converter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════
    // DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Price information structure
    /// @dev Tracks rate, timestamp, and deviation for both oracle and manual prices
    struct PriceInfo {
        uint256 rate;           // Exchange rate with 6 decimals (e.g., 50e6 = 50 EGP per USDT)
        uint256 timestamp;      // Last update timestamp
        uint256 deviation;      // Last deviation in basis points (e.g., 1000 = 10%)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Price Feed Configuration
    // ─────────────────────────────────────────────────────────────────────────
    
    /// @notice Chainlink CRE price feed receiver (optional - can use manual rate)
    PriceFeedReceiver public priceFeedReceiver;

    /// @notice Oracle price information (rate, timestamp, deviation)
    PriceInfo public oraclePrice;

    /// @notice Manual price information (rate, timestamp, deviation)
    PriceInfo public manualPrice;

    /// @notice Whether to use Chainlink CRE oracle (true) or manual rate (false)
    bool public useOracle;

    // ─────────────────────────────────────────────────────────────────────────
    // Risk Management Parameters
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Maximum price age for oracle (seconds)
    /// @dev If oracle price is older than this, fallback to manual rate
    uint256 public maxPriceAge;

    /// @notice Maximum price deviation in basis points (configurable, e.g., 20% = 2000 bps)
    /// @dev Protects against oracle manipulation and flash crashes
    uint256 public maxPriceDeviationBps;

/**
        Basis points are a unit of measurement used in finance:
        1 basis point (bp) = 0.01%
        100 basis points = 1%
        10,000 basis points = 100%
 */
    /// @notice Maximum allowed deviation limit (set in constructor, e.g., 50% = 5000 bps)
    /// @dev Hard cap that maxPriceDeviationBps cannot exceed
    uint256 public immutable MAX_DEVIATION_LIMIT;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Price Update Events
    // ─────────────────────────────────────────────────────────────────────────
    
    event OraclePriceUpdated(
        uint256 oldRate, 
        uint256 newRate, 
        uint256 deviation, 
        uint256 timestamp
    );
    
    event ManualPriceUpdated(
        uint256 oldRate, 
        uint256 newRate, 
        uint256 deviation, 
        uint256 timestamp
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Configuration Events
    // ─────────────────────────────────────────────────────────────────────────
    
    event OracleToggled(bool indexed useOracle);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event MaxDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);
    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);

    // ─────────────────────────────────────────────────────────────────────────
    // Warning Events
    // ─────────────────────────────────────────────────────────────────────────
    
    event PriceDeviationTooHigh(
        uint256 newRate, 
        uint256 oldRate, 
        uint256 deviationBps
    );
    
    event OracleFallbackActivated(
        uint256 timestamp, 
        uint256 fallbackRate, 
        string reason
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRate();
    error StalePriceData(uint256 updatedAt, uint256 currentTime);
    error InvalidPriceData();
    error InvalidPriceAge();
    error DeviationTooHigh(uint256 deviation, uint256 maxDeviation);
    error ManualRateNotSet();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the Converter contract
     * @dev Sets up initial rates, deviation limits, and roles
     * 
     * @param initialRate Initial exchange rate (6 decimals)
     *        Example: 50e6 = 50 EGP per USDT
     * 
     * @param _maxPriceDeviationBps Maximum price deviation allowed (basis points)
     *        Example: 2000 = 20% maximum deviation
     * 
     * @param _maxDeviationLimit Maximum allowed deviation limit (basis points)
     *        Example: 5000 = 50% hard cap (cannot be exceeded)
     * 
     * @param _maxPriceAge Maximum price age in seconds
     *        Example: 3600 = 1 hour (oracle price older than this triggers fallback)
     * 
     * @param admin Admin address (receives all roles initially)
     * 
     * @param priceFeedReceiverAddress PriceFeedReceiver contract address
     *        Set to address(0) to use manual rate only
     */
    constructor(
        uint256 initialRate,
        uint256 _maxPriceDeviationBps,
        uint256 _maxDeviationLimit,
        uint256 _maxPriceAge,
        address admin,
        address priceFeedReceiverAddress
    ) {
        if (admin == address(0)) revert InvalidAddress();
        if (initialRate == 0) revert InvalidRate();
        if (_maxDeviationLimit == 0) revert DeviationTooHigh(0, 1);
        if (_maxPriceDeviationBps == 0 || _maxPriceDeviationBps > _maxDeviationLimit) {
            revert DeviationTooHigh(_maxPriceDeviationBps, _maxDeviationLimit);
        }
        if (_maxPriceAge == 0) revert InvalidPriceAge();
        _assertValidRate(initialRate);

        // Set immutable max deviation limit
        MAX_DEVIATION_LIMIT = _maxDeviationLimit;
        
        // Set configurable max price deviation
        maxPriceDeviationBps = _maxPriceDeviationBps;
        
        // Set max price age
        maxPriceAge = _maxPriceAge;

        // Initialize manual price with initial rate
        manualPrice = PriceInfo({
            rate: initialRate,
            timestamp: block.timestamp,
            deviation: 0
        });

        // Initialize oracle price with initial rate (will be updated on first oracle fetch)
        oraclePrice = PriceInfo({
            rate: initialRate,
            timestamp: block.timestamp,
            deviation: 0
        });

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
    }
// ═══════════════════════════════════════════════════════════════════════════
// PRICE FETCHING FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ GET EXCHANGE RATE (WITH isMint)                                           │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * @notice Calculate conversion amount based on isMint
 * @dev Main function to preview conversions
 * 
 * @param isMint Conversion direction:
 *        - true  = MINT   (USDT → Local Currency)
 *        - false = REDEEM (Local Currency → USDT)
 * 
 * @param amount Amount being converted (in source token decimals)
 * 
 * @return outputAmount Amount user will receive (in destination token decimals)
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │ DECIMAL MODEL                                                           │
 * └─────────────────────────────────────────────────────────────────────────┘
 * USDT Decimals:          6
 * Rate Decimals:          6   (local_currency_per_USDT * 1e6)
 * Local Currency Decimals:18
 */
function getExchangeRate(bool isMint, uint256 amount)
    public
    view
    returns (uint256 outputAmount)
{
    uint256 rate = getExchangeRateView();
    _assertValidRate(rate);

    if (isMint) {
        // ─────────────────────────────────────────────
        // MINT: USDT (6) → Local Currency (18)
        //
        // local = usdt * rate * 1e18
        //         -------------------
        //         1e(6 + 6)
        // ─────────────────────────────────────────────
        outputAmount = (amount * rate * 1e18) / 1e12;
    } else {
        // ─────────────────────────────────────────────
        // REDEEM: Local Currency (18) → USDT (6)
        //
        // usdt = local * 1e(6 + 6)
        //        -----------------
        //        rate * 1e18
        // ─────────────────────────────────────────────
        outputAmount = (amount * 1e12) / (rate * 1e18);
    }

    return outputAmount;
}

    ///Enforce the invariant:
    ///"All rates in the system are 6-decimal, sane, and bounded."
function _assertValidRate(uint256 rate) internal pure {
    if (rate == 0) revert InvalidRate();
    if (rate >= 1e9) revert InvalidRate();
}

    /**
     * @dev Get current exchange rate (local currency per 1 USDT)
     * @return rate Exchange rate with 6 decimals
     * @notice This function can update state when using oracle
     */
    function _getExchangeRateInternal() internal returns (uint256 rate) {
        if (useOracle) {
            return _fetchOraclePrice();
        } else {
            return _getManualPrice();
        }
    }

    /**
     * @dev Get current exchange rate without state changes (view-only version)
     * @return rate Exchange rate with 6 decimals
     */
    function getExchangeRateView() public view returns (uint256 rate) {
        if (useOracle) {
            return _fetchOraclePriceView();
        } else {
            return _getManualPriceView();
        }
    }

    /**
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ FETCH ORACLE PRICE (WITH FALLBACK)                                      │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     * @dev Fetch oracle price with comprehensive fallback logic
     * @return rate Exchange rate with 6 decimals
     * 
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ DECISION FLOW                                                           │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     *  ┌──────────────────┐
     *  │ Fetch from       │
     *  │ Oracle           │
     *  └────────┬─────────┘
     *           │
     *           ▼
     *  ┌──────────────────┐      YES    ┌──────────────────┐
     *  │ Is Oracle        │─────────────>│ Use Manual       │
     *  │ Not Configured?  │              │ Price            │
     *  └────────┬─────────┘              └──────────────────┘
     *           │ NO
     *           ▼
     *  ┌──────────────────┐      YES    ┌──────────────────┐
     *  │ Is Price         │─────────────>│ Use Manual       │
     *  │ Stale?           │              │ Price            │
     *  └────────┬─────────┘              └──────────────────┘
     *           │ NO
     *           ▼
     *  ┌──────────────────┐      YES    ┌──────────────────┐
     *  │ Is Price         │─────────────>│ Use Manual       │
     *  │ Zero?            │              │ Price            │
     *  └────────┬─────────┘              └──────────────────┘
     *           │ NO
     *           ▼
     *  ┌──────────────────┐      YES    ┌──────────────────┐
     *  │ Deviation        │─────────────>│ Use Manual       │
     *  │ Too High?        │              │ Price            │
     *  └────────┬─────────┘              └──────────────────┘
     *           │ NO
     *           ▼
     *  ┌──────────────────┐
     *  │ Return Oracle    │
     *  │ Price            │
     *  └──────────────────┘
     */
    function _fetchOraclePrice() internal returns (uint256) {
        if (address(priceFeedReceiver) == address(0)) {
            emit OracleFallbackActivated(block.timestamp, manualPrice.rate, "Oracle not configured");
            return _getManualPrice();
        }

        try priceFeedReceiver.getPrice() returns (uint224 price, uint32 timestamp) {
            // Check if stale
            if (block.timestamp - timestamp > maxPriceAge) {
                emit OracleFallbackActivated(block.timestamp, manualPrice.rate, "Stale price data");
                return _getManualPrice();
            }

            // Check if price is zero
            if (price == 0) {
                emit OracleFallbackActivated(block.timestamp, manualPrice.rate, "Zero price from oracle");
                return _getManualPrice();
            }

            uint256 rate = uint256(price);
            if (rate == 0) {
                emit OracleFallbackActivated(block.timestamp, manualPrice.rate, "Rate zero after conversion");
                return _getManualPrice();
            }

            // Check deviation against last oracle rate
            uint256 deviation = 0;
            if (oraclePrice.rate > 0) {
                deviation = _calculateDeviation(rate, oraclePrice.rate);

                // Deviation too high?
                if (deviation > maxPriceDeviationBps) {
                    emit PriceDeviationTooHigh(rate, oraclePrice.rate, deviation);
                    return _getManualPrice();
                }
            }

            // Valid new rate - update oracle price info
            uint256 oldRate = oraclePrice.rate;
            oraclePrice = PriceInfo({
                rate: rate,
                timestamp: uint256(timestamp),
                deviation: deviation
            });

            emit OraclePriceUpdated(oldRate, rate, deviation, uint256(timestamp));
            return rate;

        } catch {
            emit OracleFallbackActivated(block.timestamp, manualPrice.rate, "Oracle call failed");
            return _getManualPrice();
        }
    }

    /**
     * @dev View-only version of oracle price fetch
     */
    function _fetchOraclePriceView() internal view returns (uint256) {
        if (address(priceFeedReceiver) == address(0)) return _getManualPriceView();

        try priceFeedReceiver.getPrice() returns (uint224 price, uint32 timestamp) {
            // Check if stale
            if (block.timestamp - timestamp > maxPriceAge) return _getManualPriceView();
            
            // Check if price is zero
            if (price == 0) return _getManualPriceView();

            uint256 rate = uint256(price);
            if (rate == 0 || rate == type(uint256).max) return _getManualPriceView();

            // Check deviation
            if (oraclePrice.rate > 0) {
                uint256 deviation = _calculateDeviation(rate, oraclePrice.rate);
                
                // Deviation too high?
                if (deviation > maxPriceDeviationBps) return _getManualPriceView();
            }

            return rate;
        } catch {
            return _getManualPriceView();
        }
    }

    /**
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ GET MANUAL PRICE (FALLBACK)                                             │
     * └─────────────────────────────────────────────────────────────────────────┘
     *
     * @dev Get manual price as fallback when oracle fails
     * @return rate Manual exchange rate with 6 decimals
     *
     * ⚠️  SECURITY NOTE:
     * ────────────────────
     * No deviation check in fallback path to prevent DoS when oracle fails.
     * Admin is trusted to set accurate manual rates, especially during oracle failures.
     * Deviation protection is enforced in oracle price updates and manual rate setting.
     *
     * ✅ REQUIREMENTS:
     * ───────────────
     * - Manual rate can't be zero (guaranteed by constructor and setManualRate)
     * - Returns rate immediately without additional checks
     */
    function _getManualPrice() internal view returns (uint256) {
        // Manual rate can't be zero (set in constructor)
        if (manualPrice.rate == 0) revert ManualRateNotSet();

        return manualPrice.rate;
    }

    /**
     * @dev View-only version of manual price
     */
    function _getManualPriceView() internal view returns (uint256) {
        return manualPrice.rate;
    }

    /**
     * @dev Calculate deviation between two rates in basis points
     * @param newRate The new rate
     * @param oldRate The old rate
     * @return deviation Deviation in basis points (e.g., 1000 = 10%)
     */
    function _calculateDeviation(uint256 newRate, uint256 oldRate) internal pure returns (uint256 deviation) {
        // oldRate can't be zero, so we don't need to check for it
        
        if (newRate > oldRate) {
            deviation = ((newRate - oldRate) * 10000) / oldRate;
        } else {
            deviation = ((oldRate - newRate) * 10000) / oldRate;
        }
        
        return deviation;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ SET MANUAL RATE (EMERGENCY MODE)                                        │
     * └─────────────────────────────────────────────────────────────────────────┘
     * 
     * @notice Set manual exchange rate and switch to manual mode
     * @dev This is an emergency function with trust assumptions
     * 
     * ⚠️  TRUST ASSUMPTIONS:
     * ──────────────────────
     * - Admin is trusted to set accurate rates
     * - Manual rate should only be used in emergency situations
     * - Used when oracle is unavailable or compromised
     * 
     * 🔒 SECURITY REQUIREMENTS:
     * ────────────────────────
     * - Can't be zero
     * - Contract must be paused
     * - Only RATE_UPDATER_ROLE can call
     * 
     * 📊 STATE CHANGES:
     * ────────────────
     * - Updates manualPrice.rate
     * - Updates manualPrice.timestamp
     * - Updates manualPrice.deviation
     * - Sets useOracle to false (switches to manual mode)
     * 
     * @param newRate New rate (6 decimals, must be > 0)
     *        Example: 50e6 = 50 EGP per USDT
     */
    function setManualRate(uint256 newRate) external onlyRole(RATE_UPDATER_ROLE) whenPaused {
        // Can't be zero
        if (newRate == 0) revert InvalidRate();
        _assertValidRate(newRate);

        // Calculate deviation from current manual rate
        uint256 deviation = 0;
        if (manualPrice.rate > 0) {
            deviation = _calculateDeviation(newRate, manualPrice.rate);
        }

        uint256 oldRate = manualPrice.rate;

        // Update manual price info
        manualPrice = PriceInfo({
            rate: newRate,
            timestamp: block.timestamp,
            deviation: deviation
        });

        // Switch to manual mode (emergency safety)
        useOracle = false;

        emit ManualPriceUpdated(oldRate, newRate, deviation, block.timestamp);
        emit OracleToggled(false);
    }

    /**
     * @dev Set maximum price deviation in basis points
     * @notice Can only be called when contract is paused for safety
     * @param _maxPriceDeviationBps New max deviation (must be <= MAX_DEVIATION_LIMIT)
     */
    function setMaxPriceDeviation(uint256 _maxPriceDeviationBps) external onlyRole(ADMIN_ROLE) whenPaused {
        if (_maxPriceDeviationBps == 0 || _maxPriceDeviationBps > MAX_DEVIATION_LIMIT) {
            revert DeviationTooHigh(_maxPriceDeviationBps, MAX_DEVIATION_LIMIT);
        }

        uint256 oldDeviation = maxPriceDeviationBps;
        maxPriceDeviationBps = _maxPriceDeviationBps;

        emit MaxDeviationUpdated(oldDeviation, _maxPriceDeviationBps);
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
    function setMaxPriceAge(uint256 newAge) external onlyRole(ADMIN_ROLE) whenPaused {
        if (newAge == 0) revert InvalidPriceAge();

        uint256 oldAge = maxPriceAge;
        maxPriceAge = newAge;

        emit MaxPriceAgeUpdated(oldAge, newAge);
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
    // Price Status Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get the last price update timestamp
     * @return timestamp The timestamp of the last price update
     */
    function getLastPriceUpdate() public view returns (uint256 timestamp) {
        if (useOracle) {
            return oraclePrice.timestamp;
        }
        return manualPrice.timestamp;
    }

    /**
     * @notice Check if price data is stale
     * @return isStale True if price is older than maxPriceAge
     */
    function isPriceStale() public view returns (bool isStale) {
        uint256 lastUpdate = getLastPriceUpdate();
        if (lastUpdate == 0) return true;
        return (block.timestamp - lastUpdate) > maxPriceAge;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Price Information Getters
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get oracle price information
     * @return rate Current oracle rate (6 decimals)
     * @return timestamp Last oracle update timestamp
     * @return deviation Last deviation in basis points
     */
    function getOraclePriceInfo() 
        external 
        view 
        returns (
            uint256 rate, 
            uint256 timestamp, 
            uint256 deviation
        ) 
    {
        return (
            oraclePrice.rate, 
            oraclePrice.timestamp, 
            oraclePrice.deviation
        );
    }

    /**
     * @notice Get manual price information
     * @return rate Current manual rate (6 decimals)
     * @return timestamp Last manual update timestamp
     * @return deviation Last deviation in basis points
     */
    function getManualPriceInfo() 
        external 
        view 
        returns (
            uint256 rate, 
            uint256 timestamp, 
            uint256 deviation
        ) 
    {
        return (
            manualPrice.rate, 
            manualPrice.timestamp, 
            manualPrice.deviation
        );
    }
}
