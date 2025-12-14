// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Looper.sol";
import "../src/Swapper.sol";
import "../src/SupplyReactive.sol";
import "../src/SwapReactive.sol";
import "../src/TransferReactive.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPool.sol";

contract IntegrationTest is Test {
    Looper public looper;
    Swapper public swapper;
    SupplyReactive public supplyReactive;
    SwapReactive public swapReactive;
    TransferReactive public transferReactive;
    
    // Sepolia testnet addresses
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    // Deployed contract addresses
    address constant DEPLOYED_LOOPER = 0x534028e697fbAF4D61854A27E6B6DBDc63Edde8c;
    address constant DEPLOYED_SWAPPER = 0x8D9E25C7b0439781c7755e01A924BbF532EDf24d;
    address constant DEPLOYED_SUPPLY_REACTIVE = 0xF2cD21975a70B9DA83e4f902Dd854B433d7F3B5E;
    address constant DEPLOYED_SWAP_REACTIVE = 0x548E710cEBD460FcD18189766F7826D5BDB554bb;
    address constant DEPLOYED_TRANSFER_REACTIVE = 0xA6b51C26dfe550dCBDcac2eb2931962612c508B9;
    
    address public user;
    address public initiator;
    uint256 public constant INITIAL_BALANCE = 10 ether;
    
    function setUp() public {
        // Fork Sepolia testnet
        vm.createFork(vm.envString("SEPOLIA_RPC_URL"));
        
        // Set up test users
        user = makeAddr("user");
        initiator = makeAddr("initiator");
        vm.deal(user, INITIAL_BALANCE);
        vm.deal(initiator, INITIAL_BALANCE);
        
        // Use deployed contracts
        looper = Looper(payable(DEPLOYED_LOOPER));
        swapper = Swapper(DEPLOYED_SWAPPER);
        supplyReactive = SupplyReactive(payable(DEPLOYED_SUPPLY_REACTIVE));
        swapReactive = SwapReactive(payable(DEPLOYED_SWAP_REACTIVE));
        transferReactive = TransferReactive(payable(DEPLOYED_TRANSFER_REACTIVE));
        
        // Deal tokens to users
        deal(WETH, user, 5 ether);
        deal(USDC, user, 10000 * 1e6);
        deal(WETH, initiator, 5 ether);
    }
    
    function testContractsAreConnected() public {
        // Verify all contracts are properly connected
        assertEq(looper.collateralToken(), WETH);
        assertEq(looper.borrowToken(), USDC);
        assertEq(address(looper.Swapper()), DEPLOYED_SWAPPER);
        
        assertEq(supplyReactive.looper(), DEPLOYED_LOOPER);
        assertEq(supplyReactive.pool(), AAVE_POOL);
        
        assertEq(swapReactive.looper(), DEPLOYED_LOOPER);
        assertEq(swapReactive.swapper(), DEPLOYED_SWAPPER);
        
        assertEq(transferReactive.looper(), DEPLOYED_LOOPER);
        assertEq(transferReactive.collateralToken(), WETH);
    }
    
    function testSwapperIntegration() public {
        vm.startPrank(user);
        
        uint256 swapAmount = 1 ether;
        uint256 wethBefore = IERC20(WETH).balanceOf(user);
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        
        // Test WETH to USDC swap
        IERC20(WETH).approve(address(swapper), swapAmount);
        uint256 usdcReceived = swapper.swapAsset(WETH, USDC, swapAmount);
        
        assertEq(IERC20(WETH).balanceOf(user), wethBefore - swapAmount);
        assertEq(IERC20(USDC).balanceOf(user), usdcBefore + usdcReceived);
        assertTrue(usdcReceived > 0);
        
        // Test reverse swap
        IERC20(USDC).approve(address(swapper), usdcReceived);
        uint256 wethReceived = swapper.swapAsset(USDC, WETH, usdcReceived);
        
        assertTrue(wethReceived > 0);
        assertTrue(wethReceived < swapAmount); // Due to slippage and fees
        
        vm.stopPrank();
    }
    
    function testLooperOperationsSequence() public {
        vm.startPrank(user);
        
        // Step 1: Transfer WETH to looper
        uint256 initialAmount = 1 ether;
        IERC20(WETH).transfer(address(looper), initialAmount);
        
        // Step 2: Supply collateral (operation 0)
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(looper));
        assertTrue(wethBalanceBefore > 0);
        
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(address(looper));
        assertEq(wethBalanceAfter, 0); // All supplied to Aave
        
        // Step 3: Borrow USDC (operation 1)
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(looper));
        
        vm.prank(address(looper));
        looper.callback(address(this), 1);
        
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(address(looper));
        assertTrue(usdcBalanceAfter > usdcBalanceBefore);
        
        // Step 4: Swap USDC back to WETH (operation 2)
        uint256 finalWethBefore = IERC20(WETH).balanceOf(address(looper));
        
        vm.prank(address(looper));
        looper.callback(address(this), 2);
        
        uint256 finalWethAfter = IERC20(WETH).balanceOf(address(looper));
        assertTrue(finalWethAfter > finalWethBefore);
        
        vm.stopPrank();
    }
    
    function testCalculateSafeBorrowAmountProgression() public {
        vm.startPrank(user);
        
        // Initially should be 0
        uint256 borrowAmount0 = looper.calculateSafeBorrowAmount();
        assertEq(borrowAmount0, 0);
        
        // Supply some collateral
        IERC20(WETH).transfer(address(looper), 1 ether);
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        // Now should be > 0
        uint256 borrowAmount1 = looper.calculateSafeBorrowAmount();
        assertTrue(borrowAmount1 > 0);
        
        // Supply more collateral
        IERC20(WETH).transfer(address(looper), 1 ether);
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        
        // Should increase
        uint256 borrowAmount2 = looper.calculateSafeBorrowAmount();
        assertTrue(borrowAmount2 > borrowAmount1);
        
        vm.stopPrank();
    }
    
    function testMultipleLeverageLoops() public {
        vm.startPrank(user);
        
        uint256 initialAmount = 0.5 ether;
        
        // Execute multiple leverage loops
        for (uint i = 0; i < 3; i++) {
            // Transfer WETH to looper
            IERC20(WETH).transfer(address(looper), initialAmount);
            
            // Execute full loop
            vm.prank(address(looper));
            looper.callback(address(this), 0); // Supply
            
            vm.prank(address(looper));
            looper.callback(address(this), 1); // Borrow
            
            vm.prank(address(looper));
            looper.callback(address(this), 2); // Swap
            
            // Check that we have some WETH back for next iteration
            uint256 wethBalance = IERC20(WETH).balanceOf(address(looper));
            if (i < 2) { // Don't check on last iteration
                assertTrue(wethBalance > 0);
            }
        }
        
        vm.stopPrank();
    }
    
    function testReactiveContractsReceiveEther() public {
        uint256 sendAmount = 0.1 ether;
        
        // Test all reactive contracts can receive ether
        vm.prank(user);
        (bool success1,) = payable(address(supplyReactive)).call{value: sendAmount}("");
        assertTrue(success1);
        
        vm.prank(user);
        (bool success2,) = payable(address(swapReactive)).call{value: sendAmount}("");
        assertTrue(success2);
        
        vm.prank(user);
        (bool success3,) = payable(address(transferReactive)).call{value: sendAmount}("");
        assertTrue(success3);
        
        // Verify balances
        assertEq(address(supplyReactive).balance, sendAmount);
        assertEq(address(swapReactive).balance, sendAmount);
        assertEq(address(transferReactive).balance, sendAmount);
    }
    
    function testSwapperEstimationAccuracy() public {
        uint256 amountIn = 1 ether;
        
        // Get estimation
        uint256 estimatedOut = swapper.estimateAmountOut(WETH, USDC, amountIn);
        
        // Execute actual swap
        vm.startPrank(user);
        IERC20(WETH).approve(address(swapper), amountIn);
        uint256 actualOut = swapper.swapAsset(WETH, USDC, amountIn);
        vm.stopPrank();
        
        // Estimation should be reasonably close to actual (within 10%)
        uint256 difference = actualOut > estimatedOut ? 
            actualOut - estimatedOut : 
            estimatedOut - actualOut;
        uint256 tolerance = estimatedOut / 10; // 10% tolerance
        
        assertTrue(difference <= tolerance);
    }
    
    function testContractOwnership() public {
        // Test that looper has proper ownership
        assertTrue(looper.owner() != address(0));
        
        // Test that only owner can call owner functions (if any)
        // This would depend on specific owner functions in the contract
    }
    
    function testErrorHandling() public {
        vm.startPrank(user);
        
        // Test operations with zero balances
        vm.prank(address(looper));
        vm.expectRevert("Collateral balance is zero");
        looper.callback(address(this), 0);
        
        vm.prank(address(looper));
        vm.expectRevert("Borrow amount is zero");
        looper.callback(address(this), 1);
        
        vm.prank(address(looper));
        vm.expectRevert("Borrow token balance is zero");
        looper.callback(address(this), 2);
        
        vm.stopPrank();
    }
    
    function testGasUsage() public {
        vm.startPrank(user);
        
        // Transfer WETH to looper
        IERC20(WETH).transfer(address(looper), 1 ether);
        
        // Measure gas for each operation
        uint256 gasBefore = gasleft();
        vm.prank(address(looper));
        looper.callback(address(this), 0);
        uint256 gasUsedSupply = gasBefore - gasleft();
        
        gasBefore = gasleft();
        vm.prank(address(looper));
        looper.callback(address(this), 1);
        uint256 gasUsedBorrow = gasBefore - gasleft();
        
        gasBefore = gasleft();
        vm.prank(address(looper));
        looper.callback(address(this), 2);
        uint256 gasUsedSwap = gasBefore - gasleft();
        
        // Log gas usage for analysis
        console.log("Gas used for supply:", gasUsedSupply);
        console.log("Gas used for borrow:", gasUsedBorrow);
        console.log("Gas used for swap:", gasUsedSwap);
        
        // Basic sanity checks (operations should use reasonable gas)
        assertTrue(gasUsedSupply > 0 && gasUsedSupply < 1000000);
        assertTrue(gasUsedBorrow > 0 && gasUsedBorrow < 1000000);
        assertTrue(gasUsedSwap > 0 && gasUsedSwap < 1000000);
        
        vm.stopPrank();
    }
}