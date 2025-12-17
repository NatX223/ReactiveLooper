// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/**
 * @title Swapper
 * @dev Contract for executing token swaps using Uniswap V3
 * @notice This contract provides functionality to swap tokens and estimate swap amounts
 *         using Uniswap V3 pools with a fixed fee tier
 */
contract Swapper {
    /** @dev Uniswap V3 SwapRouter contract address for executing swaps */
    ISwapRouter public constant swapRouter = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
    
    /** @dev Uniswap V3 Factory contract address for pool lookups */
    address public constant factoryAdd = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    
    /** @dev Pool fee tier (0.3% = 3000) used for all swaps */
    uint24 public constant poolFee = 3000;

    /**
     * @dev Event emitted when a token swap is completed
     * @param collateralToken Address of the output token received
     * @param destination Address that received the swapped tokens
     */
    event swapEvent(address indexed collateralToken, address indexed destination);

    /** @dev Constructor - no initialization required */
    constructor() {}

    /**
     * @dev Executes a token swap using Uniswap V3
     * @param inToken Address of the input token to swap from
     * @param outToken Address of the output token to swap to
     * @param amount Amount of input tokens to swap
     * @return amountOut Amount of output tokens received from the swap
     * @notice Transfers input tokens from caller, executes swap, and sends output tokens back to caller
     */
    function swapAsset(
        address inToken,
        address outToken,
        uint256 amount
    ) public returns (uint256 amountOut) {
        /** @dev Transfer input tokens from caller to this contract */
        TransferHelper.safeTransferFrom(inToken, msg.sender, address(this), amount);
        
        /** @dev Approve SwapRouter to spend input tokens */
        TransferHelper.safeApprove(inToken, address(swapRouter), amount);

        /** @dev Configure swap parameters for exact input single-hop swap */
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: outToken,
                fee: poolFee,
                recipient: msg.sender,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        /** @dev Execute the swap and get output amount */
        amountOut = swapRouter.exactInputSingle(params);

        emit swapEvent(outToken, msg.sender);
    }

    /**
     * @dev Estimates the output amount for a given input amount using Uniswap V3 oracle
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens
     * @return amount Estimated amount of output tokens that would be received
     * @notice Uses time-weighted average price from the last 2 seconds for estimation
     */
    function estimateAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (uint256 amount) {
        uint32 secondsAgo = 2;
        
        address _pool = IUniswapV3Factory(factoryAdd).getPool(
            tokenIn,
            tokenOut,
            poolFee
        );
        require(_pool != address(0), "pool for the token pair does not exist");
        address pool = _pool;
        
        /** @dev Get time-weighted average tick from oracle */
        (int24 tick, ) = OracleLibrary.consult(pool, secondsAgo);
        
        /** @dev Calculate quote based on the tick price */
        amount = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(amountIn),
            tokenIn,
            tokenOut
        );

        return amount;
    }
}