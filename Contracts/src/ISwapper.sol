// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
 * @title ISwapper
 * @dev Interface for token swapping functionality
 * @notice Defines the standard interface for contracts that can swap tokens
 */
interface ISwapper {
    /**
     * @dev Swaps one token for another
     * @param inToken Address of the input token to swap from
     * @param outToken Address of the output token to swap to
     * @param amount Amount of input tokens to swap
     * @return amountOut Amount of output tokens received from the swap
     * @notice Implementation should handle token transfers and execute the swap
     */
    function swapAsset(
        address inToken,
        address outToken,
        uint256 amount
    ) external returns (uint256 amountOut);
}