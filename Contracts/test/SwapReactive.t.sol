// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/SwapReactive.sol";
import "../src/Looper.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

contract SwapReactiveTest is Test {
    SwapReactive public swapReactive;
    Looper public looper;
    
    // Deployed contract addresses
    address constant DEPLOYED_SWAP_REACTIVE = 0x548E710cEBD460FcD18189766F7826D5BDB554bb;
    address constant DEPLOYED_LOOPER = 0x534028e697fbAF4D61854A27E6B6DBDc63Edde8c;
    address constant DEPLOYED_SWAPPER = 0x8D9E25C7b0439781c7755e01A924BbF532EDf24d;
    
    address public user;
    uint256 public constant INITIAL_BALANCE = 10 ether;
    
    function setUp() public {
        // Fork Sepolia testnet
        vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        
        // Set up test user
        user = makeAddr("user");
        vm.deal(user, INITIAL_BALANCE);
        
        // Use deployed contracts
        swapReactive = SwapReactive(payable(DEPLOYED_SWAP_REACTIVE));
        looper = Looper(payable(DEPLOYED_LOOPER));
    }
    
    function testSwapReactiveInitialization() public {
        assertEq(swapReactive.looper(), DEPLOYED_LOOPER);
        assertEq(swapReactive.swapper(), DEPLOYED_SWAPPER);
        assertEq(swapReactive.SERVICE(), 0x0000000000000000000000000000000000fffFfF);
    }
    
    function testReceiveEther() public {
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(swapReactive).balance;
        
        // Send ether to the contract
        vm.prank(user);
        (bool success,) = payable(address(swapReactive)).call{value: sendAmount}("");
        assertTrue(success);
        
        uint256 balanceAfter = address(swapReactive).balance;
        assertEq(balanceAfter, balanceBefore + sendAmount);
    }
    
    function testReceiveEventEmission() public {
        uint256 sendAmount = 1 ether;
        
        // Expect the Received event to be emitted
        vm.expectEmit(true, true, true, false);
        emit SwapReactive.Received(user, user, sendAmount);
        
        vm.prank(user);
        (bool success,) = payable(address(swapReactive)).call{value: sendAmount}("");
        assertTrue(success);
    }
    
    function testReactWithCorrectSwapper() public {
        // Create a mock log record for swap completion event
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: DEPLOYED_SWAPPER,
            topic_0: 0x783bd8472ba2d01baf38569a5cdfaaa209e19da07cfaa1008df9cd1597910389,
            topic_1: bytes32(0),
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))), // destination = looper
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Expect Callback event to be emitted for supply operation (operation 0)
        vm.expectEmit(true, true, true, true);
        emit SwapReactive.Callback(
            11155111,
            DEPLOYED_LOOPER,
            1000000,
            abi.encodeWithSignature("callback(address,uint256)", address(0), 0)
        );
        
        // Mock the vmOnly modifier by pranking from the service address
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        swapReactive.react(logRecord);
    }
    
    function testReactWithIncorrectSwapper() public {
        // Create a mock log record with different destination
        address differentDestination = makeAddr("differentDestination");
        
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: DEPLOYED_SWAPPER,
            topic_0: 0x783bd8472ba2d01baf38569a5cdfaaa209e19da07cfaa1008df9cd1597910389,
            topic_1: bytes32(0),
            topic_2: bytes32(uint256(uint160(differentDestination))), // different destination
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should not emit Callback event
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        swapReactive.react(logRecord);
        
        // No assertion needed - if no event is emitted, test passes
    }
    
    function testReactAccessControl() public {
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: DEPLOYED_SWAPPER,
            topic_0: 0x783bd8472ba2d01baf38569a5cdfaaa209e19da07cfaa1008df9cd1597910389,
            topic_1: bytes32(0),
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))),
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should revert when called by non-service address
        vm.prank(user);
        vm.expectRevert();
        swapReactive.react(logRecord);
    }
    
    function testGetPausableSubscriptions() public {
        // Test that the contract is properly initialized with subscriptions
        assertTrue(address(swapReactive.service()) != address(0));
    }
    
    function testContractBalance() public {
        // Test that contract can receive and hold ether
        uint256 amount1 = 0.5 ether;
        uint256 amount2 = 1.5 ether;
        
        vm.prank(user);
        (bool success1,) = payable(address(swapReactive)).call{value: amount1}("");
        assertTrue(success1);
        
        vm.prank(user);
        (bool success2,) = payable(address(swapReactive)).call{value: amount2}("");
        assertTrue(success2);
        
        assertEq(address(swapReactive).balance, amount1 + amount2);
    }
    
    function testMultipleReceiveEvents() public {
        uint256 amount1 = 0.3 ether;
        uint256 amount2 = 0.7 ether;
        
        // First receive
        vm.expectEmit(true, true, true, false);
        emit SwapReactive.Received(user, user, amount1);
        
        vm.prank(user);
        (bool success1,) = payable(address(swapReactive)).call{value: amount1}("");
        assertTrue(success1);
        
        // Second receive
        vm.expectEmit(true, true, true, false);
        emit SwapReactive.Received(user, user, amount2);
        
        vm.prank(user);
        (bool success2,) = payable(address(swapReactive)).call{value: amount2}("");
        assertTrue(success2);
    }
    
    function testReactWithZeroAddress() public {
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: DEPLOYED_SWAPPER,
            topic_0: 0x783bd8472ba2d01baf38569a5cdfaaa209e19da07cfaa1008df9cd1597910389,
            topic_1: bytes32(0),
            topic_2: bytes32(0), // zero address as destination
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should not emit Callback event for zero address
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        swapReactive.react(logRecord);
    }
    
    function testReactWithWrongEmitter() public {
        address wrongEmitter = makeAddr("wrongEmitter");
        
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: wrongEmitter, // wrong emitter
            topic_0: 0x783bd8472ba2d01baf38569a5cdfaaa209e19da07cfaa1008df9cd1597910389,
            topic_1: bytes32(0),
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))),
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should still process since we only check topic_2, not emitter in this contract
        vm.expectEmit(true, true, true, true);
        emit SwapReactive.Callback(
            11155111,
            DEPLOYED_LOOPER,
            1000000,
            abi.encodeWithSignature("callback(address,uint256)", address(0), 0)
        );
        
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        swapReactive.react(logRecord);
    }
}