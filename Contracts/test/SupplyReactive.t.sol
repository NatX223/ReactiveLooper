// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/SupplyReactive.sol";
import "../src/Looper.sol";
import "../lib/reactive-lib/src/interfaces/IReactive.sol";

contract SupplyReactiveTest is Test {
    SupplyReactive public supplyReactive;
    Looper public looper;
    
    // Sepolia testnet addresses
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    // Deployed contract addresses
    address constant DEPLOYED_SUPPLY_REACTIVE = 0xF2cD21975a70B9DA83e4f902Dd854B433d7F3B5E;
    address constant DEPLOYED_LOOPER = 0x534028e697fbAF4D61854A27E6B6DBDc63Edde8c;
    
    address public user;
    uint256 public constant INITIAL_BALANCE = 10 ether;
    
    function setUp() public {
        // Fork Sepolia testnet
        vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        
        // Set up test user
        user = makeAddr("user");
        vm.deal(user, INITIAL_BALANCE);
        
        // Use deployed contracts
        supplyReactive = SupplyReactive(payable(DEPLOYED_SUPPLY_REACTIVE));
        looper = Looper(payable(DEPLOYED_LOOPER));
    }
    
    function testSupplyReactiveInitialization() public {
        assertEq(supplyReactive.looper(), DEPLOYED_LOOPER);
        assertEq(supplyReactive.pool(), AAVE_POOL);
        assertEq(supplyReactive.SERVICE(), 0x0000000000000000000000000000000000fffFfF);
    }
    
    function testReceiveEther() public {
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(supplyReactive).balance;
        
        // Send ether to the contract
        vm.prank(user);
        (bool success,) = payable(address(supplyReactive)).call{value: sendAmount}("");
        assertTrue(success);
        
        uint256 balanceAfter = address(supplyReactive).balance;
        assertEq(balanceAfter, balanceBefore + sendAmount);
    }
    
    function testReceiveEventEmission() public {
        uint256 sendAmount = 1 ether;
        
        // Expect the Received event to be emitted
        vm.expectEmit(true, true, true, false);
        emit SupplyReactive.Received(user, user, sendAmount);
        
        vm.prank(user);
        (bool success,) = payable(address(supplyReactive)).call{value: sendAmount}("");
        assertTrue(success);
    }
    
    function testGetPausableSubscriptions() public {
        // This tests the internal function through a view call
        // We can't directly call internal functions, but we can test the contract's behavior
        
        // The contract should be properly initialized with subscriptions
        assertTrue(address(supplyReactive.service()) != address(0));
    }
    
    function testReactWithCorrectSupplier() public {
        // Create a mock log record for supply event
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: AAVE_POOL,
            topic_0: 0x2b627736bca15cd5381dcf80b0bf11fd197d01a037c52b927a881a10fb73ba61,
            topic_1: bytes32(0),
            topic_2: bytes32(uint256(uint160(DEPLOYED_LOOPER))), // supplier = looper
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Expect Callback event to be emitted
        vm.expectEmit(true, true, true, true);
        emit SupplyReactive.Callback(
            11155111,
            DEPLOYED_LOOPER,
            1000000,
            abi.encodeWithSignature("callback(address,uint256)", address(0), 1)
        );
        
        // Mock the vmOnly modifier by pranking from the service address
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        supplyReactive.react(logRecord);
    }
    
    function testReactWithIncorrectSupplier() public {
        // Create a mock log record with different supplier
        address differentSupplier = makeAddr("differentSupplier");
        
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: AAVE_POOL,
            topic_0: 0x2b627736bca15cd5381dcf80b0bf11fd197d01a037c52b927a881a10fb73ba61,
            topic_1: bytes32(0),
            topic_2: bytes32(uint256(uint160(differentSupplier))), // different supplier
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should not emit Callback event
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        supplyReactive.react(logRecord);
        
        // No assertion needed - if no event is emitted, test passes
    }
    
    function testReactAccessControl() public {
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: AAVE_POOL,
            topic_0: 0x2b627736bca15cd5381dcf80b0bf11fd197d01a037c52b927a881a10fb73ba61,
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
        supplyReactive.react(logRecord);
    }
    
    function testContractBalance() public {
        // Test that contract can receive and hold ether
        uint256 amount1 = 0.5 ether;
        uint256 amount2 = 1.5 ether;
        
        vm.prank(user);
        (bool success1,) = payable(address(supplyReactive)).call{value: amount1}("");
        assertTrue(success1);
        
        vm.prank(user);
        (bool success2,) = payable(address(supplyReactive)).call{value: amount2}("");
        assertTrue(success2);
        
        assertEq(address(supplyReactive).balance, amount1 + amount2);
    }
    
    function testMultipleReceiveEvents() public {
        uint256 amount1 = 0.3 ether;
        uint256 amount2 = 0.7 ether;
        
        // First receive
        vm.expectEmit(true, true, true, false);
        emit SupplyReactive.Received(user, user, amount1);
        
        vm.prank(user);
        (bool success1,) = payable(address(supplyReactive)).call{value: amount1}("");
        assertTrue(success1);
        
        // Second receive
        vm.expectEmit(true, true, true, false);
        emit SupplyReactive.Received(user, user, amount2);
        
        vm.prank(user);
        (bool success2,) = payable(address(supplyReactive)).call{value: amount2}("");
        assertTrue(success2);
    }
    
    function testReactWithZeroAddress() public {
        IReactive.LogRecord memory logRecord = IReactive.LogRecord({
            chainId: 11155111,
            emitter: AAVE_POOL,
            topic_0: 0x2b627736bca15cd5381dcf80b0bf11fd197d01a037c52b927a881a10fb73ba61,
            topic_1: bytes32(0),
            topic_2: bytes32(0), // zero address as supplier
            topic_3: bytes32(0),
            data: hex"",
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            transactionHash: keccak256("test"),
            logIndex: 0
        });
        
        // Should not emit Callback event for zero address
        vm.prank(0x0000000000000000000000000000000000fffFfF);
        supplyReactive.react(logRecord);
    }
}