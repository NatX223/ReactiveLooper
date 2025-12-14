// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title TestRunner
 * @dev Script to run all tests and provide a summary
 * @notice Use this script to execute all test suites and get a comprehensive overview
 */
contract TestRunner is Script {
    
    function run() public {
        console.log("=== ReactiveLooper Test Suite ===");
        console.log("");
        
        console.log("Available Test Files:");
        console.log("1. Looper.t.sol - Core looper contract tests");
        console.log("2. Swapper.t.sol - Token swapping functionality tests");
        console.log("3. SupplyReactive.t.sol - Supply event reactive contract tests");
        console.log("4. SwapReactive.t.sol - Swap event reactive contract tests");
        console.log("5. TransferReactive.t.sol - Transfer event reactive contract tests");
        console.log("6. Integration.t.sol - End-to-end integration tests");
        console.log("");
        
        console.log("To run individual test files:");
        console.log("forge test --match-contract LooperTest -vv");
        console.log("forge test --match-contract SwapperTest -vv");
        console.log("forge test --match-contract SupplyReactiveTest -vv");
        console.log("forge test --match-contract SwapReactiveTest -vv");
        console.log("forge test --match-contract TransferReactiveTest -vv");
        console.log("forge test --match-contract IntegrationTest -vv");
        console.log("");
        
        console.log("To run all tests:");
        console.log("forge test -vv");
        console.log("");
        
        console.log("To run tests with gas reporting:");
        console.log("forge test --gas-report -vv");
        console.log("");
        
        console.log("To run specific test functions:");
        console.log("forge test --match-test testFullLeverageLoop -vv");
        console.log("forge test --match-test testSwapWETHToUSDC -vv");
        console.log("");
        
        console.log("Environment Requirements:");
        console.log("- SEPOLIA_RPC_URL must be set in .env");
        console.log("- Contracts must be deployed to Sepolia testnet");
        console.log("- Sufficient test tokens available on testnet");
        console.log("");
        
        console.log("Test Coverage Areas:");
        console.log("- Contract initialization and configuration");
        console.log("- Individual operation testing (supply, borrow, swap)");
        console.log("- Full leverage loop workflows");
        console.log("- Reactive contract event handling");
        console.log("- Access control and security");
        console.log("- Error handling and edge cases");
        console.log("- Gas usage optimization");
        console.log("- Integration between all components");
    }
}