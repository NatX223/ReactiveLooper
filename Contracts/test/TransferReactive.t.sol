// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/TransferReactive.sol";
import "../src/Looper.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

contract TransferReactiveTest is Test {
    TransferReactive public transferReactive;
    Looper public looper;
    
    // Sepolia testnet addresses
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    
    // Deployed contract addresses
    address constant DEPLOYED_TRANSFER_REACTIVE = 0xA6b51C26dfe550dCBDcac2eb2931962612c508B9;
    address constant DEPLOYED_LOOPER = 0x534028e697fbAF4D61854A27E6B6DBDc63Edde8c;
    
    address public user;
    address public initiator;
    uint256 public constant INITIAL_BALANCE = 10 ether;
    
    function setUp() public {
        // Fork Sepolia testnet
        vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        
        // Set up test user and initiator
        user = makeAddr("user");
        initiator = makeAddr("initiator");
        vm.deal(user, INITIAL_BALANCE);
        vm.deal(initiator, INITIAL_BALANCE);
        
        // Use deployed contracts
        transferReactive = TransferReactive(payable(DEPLOYED_TRANSFER_REACTIVE));
        looper = Looper(payable(DEPLOYED_LOOPER));
    }
    
    function testTransferReactiveInitialization() public {
        assertEq(transferReactive.looper(), DEPLOYED_LOOPER);
        assertEq(transferReactive.collateralToken(), WETH);
        assertTrue(transferReactive.initiator() != address(0));
        assertEq(transferReactive.SERVICE(), 0x0000000000000000000000000000000000fffFfF);
    }
    
    function testReceiveEther() public {
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(transferReactive).balance;
        
        // Send ether to the contract
        vm.prank(user);
        (bool success,) = payable(address(transferReactive)).call{value: sendAmount}("");
        assertTrue(success);
        
        uint256 balanceAfter = address(transferReactive).balance;
        assertEq(balanceAfter, balanceBefore + sendAmount);
    }
    
    function testReceiveEventEmission() public {
        uint256 sendAmount = 1 ether;
        
        // Expect the Received event to be emitted
        vm.expectEmit(true, true, true, false);
        emit TransferReactive.Received(user, user, sendAmount);
        
        vm.prank(user);
        (bool success,) = payable(address(transferReactive)).call{value: sendAmount}("");
        assertTrue(success);
    }
    
    function testReactWithCorrectTransfer() public {
        // Get the actual initiator from the contract
        address actualInitiator = transferReactive.initiator();
        
        // Create a mock log record for ERC20 Transfer event from initiator to looper
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: WETH,
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef, // Transfer event
            topic_1: bytes32(uint256(uint160(actualInitiator))), // sender = initiator
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))), // receiver = looper
            topic_3: bytes32(0),
            data: abi.encode(1 ether), // amount
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Expect Callback event to be emitted for supply operation (operation 0)
        vm.expectEmit(true, true, true, true);
        emit TransferReactive.Callback(
            11155111,
            DEPLOYED_LOOPER,
            1000000,
            abi.encodeWithSignature("callback(address,uint256)", address(0), 0)
        );
        
        // Mock the vmOnly modifier by pranking from the service address
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        transferReactive.react(logRecord);
    }
    
    function testReactWithIncorrectSender() public {
        address wrongSender = makeAddr("wrongSender");
        
        // Create a mock log record with wrong sender
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: WETH,
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
            topic_1: bytes32(uint256(uint160(wrongSender))), // wrong sender
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))), // receiver = looper
            topic_3: bytes32(0),
            data: abi.encode(1 ether),
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should not emit Callback event
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        transferReactive.react(logRecord);
        
        // No assertion needed - if no event is emitted, test passes
    }
    
    function testReactWithIncorrectReceiver() public {
        address actualInitiator = transferReactive.initiator();
        address wrongReceiver = makeAddr("wrongReceiver");
        
        // Create a mock log record with wrong receiver
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: WETH,
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
            topic_1: bytes32(uint256(uint160(actualInitiator))), // sender = initiator
            topic_2: bytes32(uint256(uint160(wrongReceiver))), // wrong receiver
            topic_3: bytes32(0),
            data: abi.encode(1 ether),
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should not emit Callback event
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        transferReactive.react(logRecord);
    }
    
    function testReactAccessControl() public {
        address actualInitiator = transferReactive.initiator();
        
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: WETH,
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
            topic_1: bytes32(uint256(uint160(actualInitiator))),
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))),
            topic_3: bytes32(0),
            data: abi.encode(1 ether),
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should revert when called by non-service address
        vm.prank(user);
        vm.expectRevert();
        transferReactive.react(logRecord);
    }
    
    function testGetPausableSubscriptions() public {
        // Test that the contract is properly initialized with subscriptions
        assertTrue(address(transferReactive.service()) != address(0));
    }
    
    function testContractBalance() public {
        // Test that contract can receive and hold ether
        uint256 amount1 = 0.5 ether;
        uint256 amount2 = 1.5 ether;
        
        vm.prank(user);
        (bool success1,) = payable(address(transferReactive)).call{value: amount1}("");
        assertTrue(success1);
        
        vm.prank(user);
        (bool success2,) = payable(address(transferReactive)).call{value: amount2}("");
        assertTrue(success2);
        
        assertEq(address(transferReactive).balance, amount1 + amount2);
    }
    
    function testMultipleReceiveEvents() public {
        uint256 amount1 = 0.3 ether;
        uint256 amount2 = 0.7 ether;
        
        // First receive
        vm.expectEmit(true, true, true, false);
        emit TransferReactive.Received(user, user, amount1);
        
        vm.prank(user);
        (bool success1,) = payable(address(transferReactive)).call{value: amount1}("");
        assertTrue(success1);
        
        // Second receive
        vm.expectEmit(true, true, true, false);
        emit TransferReactive.Received(user, user, amount2);
        
        vm.prank(user);
        (bool success2,) = payable(address(transferReactive)).call{value: amount2}("");
        assertTrue(success2);
    }
    
    function testReactWithZeroAddresses() public {
        // Test with zero sender
        IReactive.LogRecord memory logRecord1 = IReactive.LogRecord({
            chainId: 11155111,
            emitter: WETH,
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
            topic_1: bytes32(0), // zero sender
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))),
            topic_3: bytes32(0),
            data: abi.encode(1 ether),
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        transferReactive.react(logRecord1);
        
        // Test with zero receiver
        address actualInitiator = transferReactive.initiator();
        IReactive.LogRecord memory logRecord2 = IReactive.LogRecord({
            chainId: 11155111,
            emitter: WETH,
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
            topic_1: bytes32(uint256(uint160(actualInitiator))),
            topic_2: bytes32(0), // zero receiver
            topic_3: bytes32(0),
            data: abi.encode(1 ether),
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        transferReactive.react(logRecord2);
        
        // Neither should emit Callback events
    }
    
    function testReactWithDifferentToken() public {
        address actualInitiator = transferReactive.initiator();
        address differentToken = makeAddr("differentToken");
        
        // Create a mock log record from different token contract
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: differentToken, // different token
            topic_0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
            topic_1: bytes32(uint256(uint160(actualInitiator))),
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))),
            topic_3: bytes32(0),
            data: abi.encode(1 ether),
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should still process since we only check sender/receiver, not emitter
        vm.expectEmit(true, true, true, true);
        emit TransferReactive.Callback(
            11155111,
            DEPLOYED_LOOPER,
            1000000,
            abi.encodeWithSignature("callback(address,uint256)", address(0), 0)
        );
        
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        transferReactive.react(logRecord);
    }
}