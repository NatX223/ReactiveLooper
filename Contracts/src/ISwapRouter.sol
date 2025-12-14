// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

/**
 * @title ISwapRouter
 * @dev Interface for Uniswap V3 SwapRouter contract
 * @notice Provides functions for swapping tokens via Uniswap V3 pools
 */
interface ISwapRouter {
    /**
     * @dev Parameters for exact input single-hop swaps
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param fee Pool fee tier (e.g., 3000 for 0.3%)
     * @param recipient Address to receive the output tokens
     * @param amountIn Exact amount of input tokens to swap
     * @param amountOutMinimum Minimum amount of output tokens expected
     * @param sqrtPriceLimitX96 Price limit for the swap (0 = no limit)
     */
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @dev Swaps exact amount of input tokens for as much output tokens as possible
     * @param params The swap parameters encoded as ExactInputSingleParams
     * @return amountOut The amount of output tokens received from the swap
     * @notice Executes a single-hop swap with exact input amount
     */
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}