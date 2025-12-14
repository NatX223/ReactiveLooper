// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Looper.sol";
import "../src/Swapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPool.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPriceOracle.sol";

contract LooperTest is Test {
    Looper public looper;
    Swapper public swapper;
    
    // Sepolia testnet addresses
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant AAVE_POOL_ADDRESSES_PROVIDER = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;
    address constant AAVE_PRICE_ORACLE = 0x2da88497588bf89281816106C7259e31AF45a663;
    
    // Deployed contract addresses from addresses.txt
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
        looper = Looper(payable(DEPLOYED_LOOPER));
        swapper = Swapper(DEPLOYED_SWAPPER);
        
        // Deal some tokens to user for testing
        deal(WETH, user, 5 ether);
        deal(USDC, user, 10000 * 1e6); // 10,000 USDC
    }
    
    function testLooperInitialization() public {
        assertEq(looper.collateralToken(), WETH);
        assertEq(looper.borrowToken(), USDC);
        assertTrue(address(looper.Pool()) != address(0));
        assertTrue(address(looper.priceOracle()) != address(0));
        assertTrue(address(looper.Swapper()) != address(0));
    }
    
    function testCalculateSafeBorrowAmountWithNoCollateral() public {
        uint256 borrowAmount = looper.calculateSafeBorrowAmount();
        assertEq(borrowAmount, 0);
    }
    
    function testCalculateSafeBorrowAmountWithCollateral() public {
        vm.startPrank(user);
        
        // Transfer WETH to looper
        IERC20(WETH).transfer(address(looper), 1 ether);
        
        // Supply collateral first (operation 0)
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        // Now check borrow amount
        uint256 borrowAmount = looper.calculateSafeBorrowAmount();
        assertTrue(borrowAmount > 0);
        
        vm.stopPrank();
    }
    
    function testSupplyOperation() public {
        vm.startPrank(user);
        
        // Transfer WETH to looper
        uint256 supplyAmount = 1 ether;
        IERC20(WETH).transfer(address(looper), supplyAmount);
        
        uint256 balanceBefore = IERC20(WETH).balanceOf(address(looper));
        assertTrue(balanceBefore > 0);
        
        // Execute supply operation (operation 0)
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        uint256 balanceAfter = IERC20(WETH).balanceOf(address(looper));
        assertEq(balanceAfter, 0); // All tokens should be supplied to Aave
        
        vm.stopPrank();
    }
    
    function testBorrowOperation() public {
        vm.startPrank(user);
        
        // First supply collateral
        IERC20(WETH).transfer(address(looper), 1 ether);
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(looper));
        
        // Execute borrow operation (operation 1)
        vm.prank(address(looper));
        looper.callback(address(this), 1);
        
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(address(looper));
        assertTrue(usdcBalanceAfter > usdcBalanceBefore);
        
        vm.stopPrank();
    }
    
    function testSwapOperation() public {
        vm.startPrank(user);
        
        // Give looper some USDC to swap
        deal(USDC, address(looper), 1000 * 1e6); // 1000 USDC
        
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(looper));
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(looper));
        
        // Execute swap operation (operation 2)
        vm.prank(address(looper));
        looper.callback(address(this), 2);
        
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(address(looper));
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(address(looper));
        
        assertTrue(usdcBalanceAfter < usdcBalanceBefore); // USDC should decrease
        assertTrue(wethBalanceAfter > wethBalanceBefore); // WETH should increase
        
        vm.stopPrank();
    }
    
    function testFullLeverageLoop() public {
        vm.startPrank(user);
        
        // Initial setup - transfer WETH to looper
        uint256 initialAmount = 1 ether;
        IERC20(WETH).transfer(address(looper), initialAmount);
        
        // Step 1: Supply collateral (operation 0)
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        // Step 2: Borrow USDC (operation 1)
        vm.prank(address(looper));
        looper.callback(address(this), 1);
        
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(looper));
        assertTrue(usdcBalance > 0);
        
        // Step 3: Swap USDC back to WETH (operation 2)
        vm.prank(address(looper));
        looper.callback(address(this), 2);
        
        uint256 finalWethBalance = IERC20(WETH).balanceOf(address(looper));
        assertTrue(finalWethBalance > 0); // Should have some WETH from swap
        
        vm.stopPrank();
    }
    
    function testCallbackAccessControl() public {
        // Test that only authorized senders can call callback
        vm.expectRevert();
        looper.callback(address(this), 0);
        
        // Test with wrong sender
        vm.prank(user);
        vm.expectRevert();
        looper.callback(address(this), 0);
    }
    
    function testInvalidOperation() public {
        vm.startPrank(user);
        
        // Transfer some WETH first
        IERC20(WETH).transfer(address(looper), 1 ether);
        
        // Test invalid operation number (should not revert but do nothing)
        vm.prank(address(looper));
        looper.callback(address(this), 999);
        
        vm.stopPrank();
    }
    
    function testZeroBalanceOperations() public {
        vm.startPrank(user);
        
        // Test supply with zero balance
        vm.prank(address(looper));
        vm.expectRevert("Collateral balance is zero");
        looper.callback(address(this), 0);
        
        // Test borrow with no collateral supplied
        vm.prank(address(looper));
        vm.expectRevert("Borrow amount is zero");
        looper.callback(address(this), 1);
        
        // Test swap with zero USDC balance
        vm.prank(address(looper));
        vm.expectRevert("Borrow token balance is zero");
        looper.callback(address(this), 2);
        
        vm.stopPrank();
    }
}