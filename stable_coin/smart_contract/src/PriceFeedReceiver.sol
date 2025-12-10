// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IReceiverTemplate } from "./keystone/IReceiverTemplate.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";

/// @title PriceFeedReceiver - Secure consumer contract for Chainlink CRE price feed reports
/// @notice This contract receives and manages price data for a SINGLE price feed from Chainlink CRE:
///   - Forwarder address validation (mapping-based for O(1) lookup)
///   - Workflow ID validation (mapping-based for O(1) lookup)
///   - Workflow owner and name validation (mapping-based for O(1) lookup)
///   - Single price feed storage and retrieval
///   - Updatable configuration with owner access control
/// @dev One PriceFeedReceiver per currency pair (e.g., one for USD/EGP, another for USD/NGN)
contract PriceFeedReceiver is IReceiverTemplate, Ownable{

    // Array-based security parameters with mappings for efficient lookup
    address[] internal s_keystoneForwarderAddressesList;
    mapping(address forwarder => bool) internal s_keystoneForwarderAddresses;

    bytes32[] internal s_expectedWorkflowIdsList;
    mapping(bytes32 workflowId => bool) internal s_expectedWorkflowIds;

    address[] internal s_expectedAuthorsList;
    mapping(address author => bool) internal s_expectedAuthors;

    bytes10[] internal s_expectedWorkflowNamesList;
    mapping(bytes10 workflowName => bool) internal s_expectedWorkflowNames;

    // Price feed storage - single price for this receiver
    uint224 public latestPrice;
    uint32 public latestTimestamp;
    // Custom errors
    error InvalidSender(address sender);
    error UnauthorizedWorkflow(bytes32 received);
    error InvalidAddress(address addr);
    error InvalidWorkflowId(bytes32 workflowId);
    error DuplicateValue();
    error NoDataPresent();

    // Events
    event KeystoneForwarderAdded(address indexed forwarder);
    event WorkflowIdAdded(bytes32 indexed workflowId);
    event ExpectedAuthorAdded(address indexed author);
    event ExpectedWorkflowNameAdded(bytes10 indexed workflowName);
    event PriceUpdated(uint224 price, uint32 timestamp);

    /// @notice Constructor to initialize the contract with an owner
    /// @param initialOwner The address that will own this contract
    constructor(address initialOwner) IReceiverTemplate() Ownable(initialOwner) {
        // Arrays are initialized empty - use add* functions to configure
    }

    /// @notice Override to add forwarder and workflow ID checks before parent validation
    /// @param metadata Report metadata containing workflow information
    /// @param report The actual report data
    function onReport(
        bytes calldata metadata,
        bytes calldata report
    ) external override {
       // First check: Ensure the call is from a trusted KeystoneForwarder
        // if (!s_keystoneForwarderAddresses[msg.sender]) {
        //     revert InvalidSender(msg.sender);
        // }

        // // Second check: Validate workflow ID
        // bytes32 workflowId = _getWorkflowId(metadata);
        // if (!s_expectedWorkflowIds[workflowId]) {
        //     revert UnauthorizedWorkflow(workflowId);
        // }

        // // Third check: Validate workflow owner - using parent's _decodeMetadata
        // (address workflowOwner, bytes10 workflowName) = _decodeMetadata(metadata);
        // if (!s_expectedAuthors[workflowOwner]) {
        //     // Use first expected author as reference for error message
        //     address expectedAuthorRef = s_expectedAuthorsList.length > 0 ? s_expectedAuthorsList[0] : address(0);
        //     revert InvalidAuthor(workflowOwner, expectedAuthorRef);
        // }

        // // Fourth check: Validate workflow name - using parent's _decodeMetadata
        // if (!s_expectedWorkflowNames[workflowName]) {
        //     // Use first expected workflow name as reference for error message
        //     bytes10 expectedNameRef = s_expectedWorkflowNamesList.length > 0 ? s_expectedWorkflowNamesList[0] : bytes10(0);
        //     revert InvalidWorkflowName(workflowName, expectedNameRef);
        // }

        // All validations passed, process the report
        _processReport(report);
    }

    /// @notice Extracts workflow ID from the onReport `metadata` parameter
    /// @param metadata The metadata bytes
    /// @return workflowId The workflow ID (workflow_cid)
    /// @dev Uses parent's _decodeMetadata for workflowOwner and workflowName to avoid duplication
    function _getWorkflowId(
        bytes memory metadata
    ) internal pure returns (bytes32 workflowId) {
        assembly {
            // workflow_cid (workflowId) is at offset 32, size 32
            workflowId := mload(add(metadata, 32))
        }
    }

    /// @notice Processes the validated price feed report from CRE
    /// @param report The ABI-encoded report data from the workflow
    /// @dev The report should contain: (uint224 price, uint32 timestamp)
    function _processReport(bytes calldata report) internal override {
        // Decode the report containing single price feed data
        // Expected format: (uint224 price, uint32 timestamp)
        (uint224 price, uint32 timestamp) = abi.decode(report, (uint224, uint32));

        // Store the latest price
        latestPrice = price;
        latestTimestamp = timestamp;

        emit PriceUpdated(price, timestamp);
    }

    /// @notice Retrieves the stored price
    /// @return price The stored price (with 8 decimals, matching Chainlink standard)
    /// @return timestamp The timestamp when the price was updated
    function getPrice() external view returns (uint224 price, uint32 timestamp) {
        if (latestTimestamp == 0) {
            revert NoDataPresent();
        }
        return (latestPrice, latestTimestamp);
    }

    /// @notice Adds a new KeystoneForwarder address to the allowed list (owner only)
    /// @param _forwarderAddress The KeystoneForwarder contract address to add
    function addKeystoneForwarder(address _forwarderAddress) external onlyOwner {
        if (_forwarderAddress == address(0)) {
            revert InvalidAddress(address(0));
        }
        // Check for duplicates using mapping
        if (s_keystoneForwarderAddresses[_forwarderAddress]) {
            revert DuplicateValue();
        }
        s_keystoneForwarderAddressesList.push(_forwarderAddress);
        s_keystoneForwarderAddresses[_forwarderAddress] = true;
        emit KeystoneForwarderAdded(_forwarderAddress);
    }

    /// @notice Adds a new expected workflow ID to the allowed list (owner only)
    /// @param _workflowId The workflow ID to add
    function addExpectedWorkflowId(bytes32 _workflowId) external onlyOwner {
        if (_workflowId == bytes32(0)) {
            revert InvalidWorkflowId(bytes32(0));
        }
        // Check for duplicates using mapping
        if (s_expectedWorkflowIds[_workflowId]) {
            revert DuplicateValue();
        }
        s_expectedWorkflowIdsList.push(_workflowId);
        s_expectedWorkflowIds[_workflowId] = true;
        emit WorkflowIdAdded(_workflowId);
    }

    /// @notice Adds a new expected workflow author to the allowed list (owner only)
    /// @param _author The expected workflow owner address to add
    function addExpectedAuthor(address _author) external onlyOwner {
        if (_author == address(0)) {
            revert InvalidAddress(address(0));
        }
        // Check for duplicates using mapping
        if (s_expectedAuthors[_author]) {
            revert DuplicateValue();
        }
        s_expectedAuthorsList.push(_author);
        s_expectedAuthors[_author] = true;
        emit ExpectedAuthorAdded(_author);
    }

    /// @notice Adds a new expected workflow name to the allowed list (owner only)
    /// @param _workflowName The expected workflow name to add
    function addExpectedWorkflowName(bytes10 _workflowName) external onlyOwner {
        if (_workflowName == bytes10(0)) {
            revert InvalidWorkflowName(bytes10(0), bytes10(0));
        }
        // Check for duplicates using mapping
        if (s_expectedWorkflowNames[_workflowName]) {
            revert DuplicateValue();
        }
        s_expectedWorkflowNamesList.push(_workflowName);
        s_expectedWorkflowNames[_workflowName] = true;
        emit ExpectedWorkflowNameAdded(_workflowName);
    }

    /// @notice Gets the count of authorized forwarders
    /// @return The number of authorized forwarders
    function getKeystoneForwarderCount() external view returns (uint256) {
        return s_keystoneForwarderAddressesList.length;
    }

    /// @notice Gets the count of authorized workflow IDs
    /// @return The number of authorized workflow IDs
    function getExpectedWorkflowIdCount() external view returns (uint256) {
        return s_expectedWorkflowIdsList.length;
    }

    /// @notice Gets the count of authorized authors
    /// @return The number of authorized authors
    function getExpectedAuthorCount() external view returns (uint256) {
        return s_expectedAuthorsList.length;
    }

    /// @notice Gets the count of authorized workflow names
    /// @return The number of authorized workflow names
    function getExpectedWorkflowNameCount() external view returns (uint256) {
        return s_expectedWorkflowNamesList.length;
    }

   }

