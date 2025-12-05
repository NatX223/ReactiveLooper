
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';

contract Uniswap {

    ISwapRouter public constant swapRouter = ISwapRouter(Router);

    //the transaction event that is emmitted everytime a transaction is made
    event transaction(address payer, address receiver, uint _price, uint time);

    address deployer;

    address public constant Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // the router contract address
    address public constant factoryAdd = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000;
    // the address of USDT (default stable coin), please cross check if this is the right USDT address for uniswap
    // this address might be wrong
    address public constant purchaseToken = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address public constant wMatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    constructor (address _deployer) {
        deployer = _deployer;
    }

    // the buyAsset function follows the swapexactinput example from uniswap documentation 
    function buyAsset (
        // the token the user is buying
        address _assetToken,
        // the amount the user intends to buy
        uint _amount,
        // the receivers address i.e the smart contract address
        address _receiver
        ) public returns(uint amountOut) {
            // getting the amountoutminimum
            // uint amount = estimateAmountOut(_assetToken, _amount);
            // the price is actually to be calculated using an oracle
            TransferHelper.safeTransferFrom(purchaseToken, msg.sender, address(this), _amount);
            TransferHelper.safeApprove(purchaseToken, address(swapRouter), _amount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: purchaseToken,
                tokenOut: _assetToken,
                fee: poolFee,
                recipient: _receiver,
                deadline: block.timestamp + 10,
                amountIn: _amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap and gets the amount paid to the receiver.
        amountOut = swapRouter.exactInputSingle(params);
        emit transaction(msg.sender, _receiver, amountOut, block.timestamp);       
    }

    // Uniswap price oracle for determining the equivalent amount to be paid
    // get the address of USDT for mumbai testnet
    function estimateAmountOut (address tokenOut, uint amountIn) internal view returns (uint amount) {
        uint32 secondsAgo = 2;
        address _pool = IUniswapV3Factory(factoryAdd).getPool(
            purchaseToken, tokenOut, poolFee
        );
        require(_pool != address(0), "pool for the token pair does not exist");
        address pool = _pool;
        (int24 tick, uint128 meanLiq) = OracleLibrary.consult(pool, secondsAgo);
        amount = OracleLibrary.getQuoteAtTick(
            tick, uint128(amountIn), purchaseToken, tokenOut
        );

        return amount;
    }

        function getUSDT (
            uint amount
        ) public returns(uint amountOut) {
            // the price is actually to be calculated using an oracle
            TransferHelper.safeTransferFrom(wMatic, msg.sender, address(this), amount);
            TransferHelper.safeApprove(wMatic, address(swapRouter), amount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: wMatic,
                tokenOut: purchaseToken,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp + 10,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap and gets the amount paid to the receiver.
        amountOut = swapRouter.exactInputSingle(params);
    }

        function sellToken (
        // the token the user is buying
        address _assetToken,
        // the amount the user intends to buy
        uint _amount,
        // the receivers address i.e the smart contract address
        address _receiver
        ) public returns(uint amountOut) {
            // getting the amountoutminimum
            // uint amount = estimateAmountOut(_assetToken, _amount);
            // the price is actually to be calculated using an oracle
            TransferHelper.safeApprove(_assetToken, address(swapRouter), _amount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _assetToken,
                tokenOut: purchaseToken,
                fee: poolFee,
                recipient: _receiver,
                deadline: block.timestamp + 10,
                amountIn: _amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap and gets the amount paid to the receiver.
        amountOut = swapRouter.exactInputSingle(params);
        emit transaction(msg.sender, _receiver, amountOut, block.timestamp);       
    }

}