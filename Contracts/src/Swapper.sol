// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Swapper {
    ISwapRouter public constant swapRouter = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
    address public constant factoryAdd = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    uint24 public constant poolFee = 3000;

    constructor() {}

    function swapAsset(
        address inToken,
        address outToken,
        uint256 amount
    ) public returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(inToken, msg.sender, address(this), amount);
        TransferHelper.safeApprove(inToken, address(swapRouter), amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: outToken,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp + 10,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

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
        (int24 tick, ) = OracleLibrary.consult(pool, secondsAgo);
        amount = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(amountIn),
            tokenIn,
            tokenOut
        );

        return amount;
    }
}
