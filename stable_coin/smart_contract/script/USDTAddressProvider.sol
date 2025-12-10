// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title USDTAddressProvider
 * @notice Provides USDT addresses for different networks
 * @dev Supports mainnet, testnets, and L2s
 */
library USDTAddressProvider {

    // Network Chain IDs
    uint256 constant MAINNET = 1;
    uint256 constant SEPOLIA = 11155111;
    uint256 constant GOERLI = 5;
    uint256 constant POLYGON = 137;
    uint256 constant POLYGON_MUMBAI = 80001;
    uint256 constant ARBITRUM = 42161;
    uint256 constant ARBITRUM_SEPOLIA = 421614;
    uint256 constant OPTIMISM = 10;
    uint256 constant OPTIMISM_SEPOLIA = 11155420;
    uint256 constant BASE = 8453;
    uint256 constant BASE_SEPOLIA = 84532;
    uint256 constant AVALANCHE = 43114;
    uint256 constant AVALANCHE_FUJI = 43113;
    uint256 constant BSC = 56;
    uint256 constant BSC_TESTNET = 97;

    /**
     * @notice Get USDT address for current network
     * @return USDT contract address for the current chain
     */
    function getUSDTAddress() internal view returns (address) {
        return getUSDTAddressForChain(block.chainid);
    }

    /**
     * @notice Get USDT address for specific chain ID
     * @param chainId The chain ID to get USDT address for
     * @return USDT contract address, or address(0) if not supported
     */
    function getUSDTAddressForChain(uint256 chainId) internal pure returns (address) {
        // Ethereum Mainnet
        if (chainId == MAINNET) {
            return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        }

        // Ethereum Testnets
        if (chainId == SEPOLIA) {
            return 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // Sepolia USDT
        }

        if (chainId == GOERLI) {
            return 0x509Ee0d083DdF8AC028f2a56731412edD63223B9; // Goerli USDT (deprecated)
        }

        // Polygon
        if (chainId == POLYGON) {
            return 0xc2132D05D31c914a87C6611C10748AEb04B58e8F; // USDT (PoS)
        }

        if (chainId == POLYGON_MUMBAI) {
            return 0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832; // Mumbai USDT
        }

        // Arbitrum
        if (chainId == ARBITRUM) {
            return 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // Arbitrum USDT
        }

        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x0000000000000000000000000000000000000000; // Not deployed yet, use mock
        }

        // Optimism
        if (chainId == OPTIMISM) {
            return 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58; // Optimism USDT
        }

        if (chainId == OPTIMISM_SEPOLIA) {
            return 0x0000000000000000000000000000000000000000; // Not deployed yet, use mock
        }

        // Base
        if (chainId == BASE) {
            return 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2; // Base USDT
        }

        if (chainId == BASE_SEPOLIA) {
            return 0x0000000000000000000000000000000000000000; // Not deployed yet, use mock
        }

        // Avalanche
        if (chainId == AVALANCHE) {
            return 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7; // Avalanche USDT
        }

        if (chainId == AVALANCHE_FUJI) {
            return 0x0000000000000000000000000000000000000000; // Not deployed yet, use mock
        }

        // BSC
        if (chainId == BSC) {
            return 0x55d398326f99059fF775485246999027B3197955; // BSC USDT
        }

        if (chainId == BSC_TESTNET) {
            return 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd; // BSC Testnet USDT
        }

        // Unknown network - return zero address (caller should deploy mock)
        return address(0);
    }

    /**
     * @notice Check if USDT is deployed on this network
     * @return true if USDT address is known for this network
     */
    function isUSDTDeployed() internal view returns (bool) {
        return getUSDTAddress() != address(0);
    }

    /**
     * @notice Check if USDT is deployed on specific chain
     * @param chainId Chain ID to check
     * @return true if USDT address is known for the chain
     */
    function isUSDTDeployedOnChain(uint256 chainId) internal pure returns (bool) {
        return getUSDTAddressForChain(chainId) != address(0);
    }

    /**
     * @notice Get network name for chain ID
     * @param chainId Chain ID
     * @return Network name
     */
    function getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == MAINNET) return "Ethereum Mainnet";
        if (chainId == SEPOLIA) return "Sepolia";
        if (chainId == GOERLI) return "Goerli";
        if (chainId == POLYGON) return "Polygon";
        if (chainId == POLYGON_MUMBAI) return "Polygon Mumbai";
        if (chainId == ARBITRUM) return "Arbitrum One";
        if (chainId == ARBITRUM_SEPOLIA) return "Arbitrum Sepolia";
        if (chainId == OPTIMISM) return "Optimism";
        if (chainId == OPTIMISM_SEPOLIA) return "Optimism Sepolia";
        if (chainId == BASE) return "Base";
        if (chainId == BASE_SEPOLIA) return "Base Sepolia";
        if (chainId == AVALANCHE) return "Avalanche C-Chain";
        if (chainId == AVALANCHE_FUJI) return "Avalanche Fuji";
        if (chainId == BSC) return "BNB Smart Chain";
        if (chainId == BSC_TESTNET) return "BSC Testnet";

        return "Unknown Network";
    }

    /**
     * @notice Get current network name
     * @return Network name for current chain
     */
    function getCurrentNetworkName() internal view returns (string memory) {
        return getNetworkName(block.chainid);
    }
}
