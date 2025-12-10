// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ExecutionProxy - Executes arbitrary signed data with access control
/// @notice This contract can execute arbitrary calls but only when called by the authorized SettlementReceiver
contract ExecutionProxy {
    // The authorized SettlementReceiver contract address
    address public immutable authorizedCaller;



    // Custom errors
    error UnauthorizedCaller(address caller, address expected);
    error ExecutionReverted(bytes reason);

    /// @notice Constructor sets the authorized caller (SettlementReceiver)
    /// @param _authorizedCaller The SettlementReceiver contract address
    constructor(address _authorizedCaller) {
        if (_authorizedCaller == address(0)) {
            revert UnauthorizedCaller(address(0), _authorizedCaller);
        }
        authorizedCaller = _authorizedCaller;
    }

   
}

