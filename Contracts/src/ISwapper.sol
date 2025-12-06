// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
interface ISwapper {
    function swapAsset(
        address inToken,
        address outToken,
        uint256 amount
    ) external returns (uint256 amountOut);
}