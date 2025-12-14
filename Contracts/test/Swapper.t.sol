// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Swapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapperTest is Test {
    Swapper public swapper;
    
    // Sepolia testnet addresses
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    
    // Deployed swapper address
    address constant DEPLOYED_SWAPPER = 0x8D9E25C7b0439781c7755e01A924BbF532EDf24d;
    
    address public user;
    uint256 public constant INITIAL_BALANCE = 10 ether;
    
    function setUp() public {
        // Fork Sepolia testnet
        vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        
        // Set up test user
        user = makeAddr("user");
        vm.deal(user, INITIAL_BALANCE);
        
        // Use deployed swapper
        swapper = Swapper(DEPLOYED_SWAPPER);
        
        // Deal some tokens to user for testing
        deal(WETH, user, 5 ether);
        deal(USDC, user, 10000 * 1e6); // 10,000 USDC
    }
    
    function testSwapperInitialization() public {
        assertTrue(address(swapper.swapRouter()) != address(0));
        assertEq(swapper.factoryAdd(), 0x0227628f3F023bb0B980b67D528571c95c6DaC1c);
        assertEq(swapper.poolFee(), 3000);
    }
    
    function testSwapWETHToUSDC() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 1 ether;
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(user);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(user);
        
        // Approve swapper to spend WETH
        IERC20(WETH).approve(address(swapper), swapAmount);
        
        // Execute swap
        uint256 amountOut = swapper.swapAsset(WETH, USDC, swapAmount);
        
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(user);
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(user);
        
        // Verify balances changed correctly
        assertEq(wethBalanceAfter, wethBalanceBefore - swapAmount);
        assertEq(usdcBalanceAfter, usdcBalanceBefore + amountOut);
        assertTrue(amountOut > 0);
        
        vm.stopPrank();
    }
    
    function testSwapUSDCToWETH() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 1000 * 1e6; // 1000 USDC
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(user);
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(user);
        
        // Approve swapper to spend USDC
        IERC20(USDC).approve(address(swapper), swapAmount);
        
        // Execute swap
        uint256 amountOut = swapper.swapAsset(USDC, WETH, swapAmount);
        
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(user);
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(user);
        
        // Verify balances changed correctly
        assertEq(usdcBalanceAfter, usdcBalanceBefore - swapAmount);
        assertEq(wethBalanceAfter, wethBalanceBefore + amountOut);
        assertTrue(amountOut > 0);
        
        vm.stopPrank();
    }
    
    function testEstimateAmountOut() public {
        uint256 amountIn = 1 ether;
        
        uint256 estimatedOut = swapper.estimateAmountOut(WETH, USDC, amountIn);
        assertTrue(estimatedOut > 0);
        
        // The estimate should be reasonable (not zero or extremely high)
        assertTrue(estimatedOut < 10000 * 1e6); // Less than 10,000 USDC for 1 WETH
        assertTrue(estimatedOut > 100 * 1e6);   // More than 100 USDC for 1 WETH
    }
    
    function testEstimateAmountOutReverse() public {
        uint256 amountIn = 1000 * 1e6; // 1000 USDC
        
        uint256 estimatedOut = swapper.estimateAmountOut(USDC, WETH, amountIn);
        assertTrue(estimatedOut > 0);
        
        // The estimate should be reasonable
        assertTrue(estimatedOut < 1 ether);     // Less than 1 WETH for 1000 USDC
        assertTrue(estimatedOut > 0.1 ether);   // More than 0.1 WETH for 1000 USDC
    }
    
    function testSwapEventEmission() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 1 ether;
        
        // Approve swapper to spend WETH
        IERC20(WETH).approve(address(swapper), swapAmount);
        
        // Expect the swapEvent to be emitted
        vm.expectEmit(true, true, false, false);
        emit Swapper.swapEvent(USDC, user);
        
        // Execute swap
        swapper.swapAsset(WETH, USDC, swapAmount);
        
        vm.stopPrank();
    }
    
    function testSwapWithInsufficientAllowance() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 1 ether;
        
        // Don't approve or approve insufficient amount
        IERC20(WETH).approve(address(swapper), swapAmount - 1);
        
        // Should revert due to insufficient allowance
        vm.expectRevert();
        swapper.swapAsset(WETH, USDC, swapAmount);
        
        vm.stopPrank();
    }
    
    function testSwapWithInsufficientBalance() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 100 ether; // More than user has
        
        // Approve large amount
        IERC20(WETH).approve(address(swapper), swapAmount);
        
        // Should revert due to insufficient balance
        vm.expectRevert();
        swapper.swapAsset(WETH, USDC, swapAmount);
        
        vm.stopPrank();
    }
    
    function testSwapZeroAmount() public {
        vm.startPrank(user);
        
        // Approve swapper
        IERC20(WETH).approve(address(swapper), 1 ether);
        
        // Should revert or return 0 for zero amount
        vm.expectRevert();
        swapper.swapAsset(WETH, USDC, 0);
        
        vm.stopPrank();
    }
    
    function testEstimateForNonExistentPool() public {
        // Use addresses that don't have a pool
        address fakeToken1 = makeAddr("fakeToken1");
        address fakeToken2 = makeAddr("fakeToken2");
        
        vm.expectRevert("pool for the token pair does not exist");
        swapper.estimateAmountOut(fakeToken1, fakeToken2, 1 ether);
    }
    
    function testMultipleSwaps() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 0.5 ether;
        
        // Approve swapper for multiple swaps
        IERC20(WETH).approve(address(swapper), swapAmount * 3);
        
        uint256 initialWETH = IERC20(WETH).balanceOf(user);
        uint256 initialUSDC = IERC20(USDC).balanceOf(user);
        
        // Execute multiple swaps
        uint256 out1 = swapper.swapAsset(WETH, USDC, swapAmount);
        uint256 out2 = swapper.swapAsset(WETH, USDC, swapAmount);
        uint256 out3 = swapper.swapAsset(WETH, USDC, swapAmount);
        
        uint256 finalWETH = IERC20(WETH).balanceOf(user);
        uint256 finalUSDC = IERC20(USDC).balanceOf(user);
        
        // Verify total changes
        assertEq(finalWETH, initialWETH - (swapAmount * 3));
        assertEq(finalUSDC, initialUSDC + out1 + out2 + out3);
        
        vm.stopPrank();
    }
}