// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/access/Ownable.sol";

/**
 * @title MockUSDT
 * @notice Mock USDT token for testing on networks where USDT isn't deployed
 * @dev Mimics real USDT with 6 decimals and includes mint functionality for testing
 */
contract MockUSDT is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;

    /**
     * @notice Deploy mock USDT
     * @dev Deploys with standard USDT parameters (6 decimals)
     */
    constructor() ERC20("Mock Tether USD", "USDT") Ownable(msg.sender) {
        // Mint initial supply to deployer for testing
        _mint(msg.sender, 1_000_000_000 * 10 ** DECIMALS); // 1 billion USDT
    }

    /**
     * @notice Returns token decimals (6 like real USDT)
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Mint tokens for testing
     * @param to Recipient address
     * @param amount Amount to mint (in 6 decimal format)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens for testing
     * @param from Address to burn from
     * @param amount Amount to burn (in 6 decimal format)
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @notice Fund an address with USDT for testing
     * @param recipient Address to fund
     * @param amount Amount in USDT (will be converted to 6 decimals)
     */
    function fund(address recipient, uint256 amount) external {
        _mint(recipient, amount * 10 ** DECIMALS);
    }
}
