// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/PriceFeedReceiver.sol";

contract PriceFeedReceiverTest is Test {
    PriceFeedReceiver public receiver;
    address public owner;
    address public forwarder;
    address public author;

    bytes32 public workflowId;
    bytes10 public workflowName;

    event PriceUpdated(uint224 price, uint32 timestamp);

    function setUp() public {
        owner = address(this);
        forwarder = address(0x1);
        author = address(0x2);
        workflowId = keccak256("workflow1");
        workflowName = bytes10("USD_EGP");

        receiver = new PriceFeedReceiver(owner);

        // Configure receiver
        receiver.addKeystoneForwarder(forwarder);
        receiver.addExpectedWorkflowId(workflowId);
        receiver.addExpectedAuthor(author);
        receiver.addExpectedWorkflowName(workflowName);
    }

    function testInitialState() public view {
        assertEq(receiver.latestPrice(), 0);
        assertEq(receiver.latestTimestamp(), 0);
        assertEq(receiver.getKeystoneForwarderCount(), 1);
        assertEq(receiver.getExpectedWorkflowIdCount(), 1);
    }

    function testAddKeystoneForwarder() public {
        address newForwarder = address(0x3);
        receiver.addKeystoneForwarder(newForwarder);
        assertEq(receiver.getKeystoneForwarderCount(), 2);
    }

    function testCannotAddDuplicateForwarder() public {
        vm.expectRevert(PriceFeedReceiver.DuplicateValue.selector);
        receiver.addKeystoneForwarder(forwarder);
    }

    function testCannotAddZeroAddressForwarder() public {
        vm.expectRevert(abi.encodeWithSelector(PriceFeedReceiver.InvalidAddress.selector, address(0)));
        receiver.addKeystoneForwarder(address(0));
    }

    function testAddWorkflowId() public {
        bytes32 newId = keccak256("workflow2");
        receiver.addExpectedWorkflowId(newId);
        assertEq(receiver.getExpectedWorkflowIdCount(), 2);
    }

    function testCannotAddDuplicateWorkflowId() public {
        vm.expectRevert(PriceFeedReceiver.DuplicateValue.selector);
        receiver.addExpectedWorkflowId(workflowId);
    }

    function testAddAuthor() public {
        address newAuthor = address(0x4);
        receiver.addExpectedAuthor(newAuthor);
        assertEq(receiver.getExpectedAuthorCount(), 2);
    }

    function testAddWorkflowName() public {
        bytes10 newName = bytes10("USD_NGN");
        receiver.addExpectedWorkflowName(newName);
        assertEq(receiver.getExpectedWorkflowNameCount(), 2);
    }

    function testOnReport() public {
        // Prepare metadata
        bytes memory metadata = abi.encodePacked(
            workflowId,      // 32 bytes
            workflowName,    // 10 bytes
            author          // 20 bytes
        );

        // Prepare report
        uint224 price = 5000000000; // 50.00 with 8 decimals
        uint32 timestamp = uint32(block.timestamp);
        bytes memory report = abi.encode(price, timestamp);

        // Call onReport from forwarder
        vm.prank(forwarder);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdated(price, timestamp);
        receiver.onReport(metadata, report);

        // Verify price stored
        assertEq(receiver.latestPrice(), price);
        assertEq(receiver.latestTimestamp(), timestamp);
    }

    function testGetPrice() public {
        // Setup price
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        uint224 price = 5000000000;
        uint32 timestamp = uint32(block.timestamp);
        bytes memory report = abi.encode(price, timestamp);

        vm.prank(forwarder);
        receiver.onReport(metadata, report);

        // Get price
        (uint224 returnedPrice, uint32 returnedTimestamp) = receiver.getPrice();
        assertEq(returnedPrice, price);
        assertEq(returnedTimestamp, timestamp);
    }

    function testGetPriceRevertsWhenNoData() public {
        vm.expectRevert(PriceFeedReceiver.NoDataPresent.selector);
        receiver.getPrice();
    }

    function testOnReportRevertsFromUnauthorizedSender() public {
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);
        bytes memory report = abi.encode(uint224(5000000000), uint32(block.timestamp));

        address unauthorized = address(0x999);
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(PriceFeedReceiver.InvalidSender.selector, unauthorized));
        receiver.onReport(metadata, report);
    }

    function testOnReportRevertsWithInvalidWorkflowId() public {
        bytes32 invalidId = keccak256("invalid");
        bytes memory metadata = abi.encodePacked(invalidId, workflowName, author);
        bytes memory report = abi.encode(uint224(5000000000), uint32(block.timestamp));

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(PriceFeedReceiver.UnauthorizedWorkflow.selector, invalidId));
        receiver.onReport(metadata, report);
    }

    function testOnlyOwnerCanAddForwarder() public {
        address notOwner = address(0x999);
        vm.prank(notOwner);
        vm.expectRevert();
        receiver.addKeystoneForwarder(address(0x5));
    }

    function testPriceUpdate() public {
        bytes memory metadata = abi.encodePacked(workflowId, workflowName, author);

        // First update
        uint224 price1 = 5000000000;
        uint32 timestamp1 = uint32(block.timestamp);
        bytes memory report1 = abi.encode(price1, timestamp1);

        vm.prank(forwarder);
        receiver.onReport(metadata, report1);
        assertEq(receiver.latestPrice(), price1);

        // Second update
        vm.warp(block.timestamp + 3600);
        uint224 price2 = 5100000000;
        uint32 timestamp2 = uint32(block.timestamp);
        bytes memory report2 = abi.encode(price2, timestamp2);

        vm.prank(forwarder);
        receiver.onReport(metadata, report2);
        assertEq(receiver.latestPrice(), price2);
        assertEq(receiver.latestTimestamp(), timestamp2);
    }
}
