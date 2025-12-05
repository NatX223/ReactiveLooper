// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import '../lib/reactive-lib/src/abstract-base/AbstractCallback.sol';
import '../lib/openzeppelin-contracts/contracts/access/Ownable.sol';
import '../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import './PoolInterface.sol';

contract TokenSupplier is AbstractCallback, Ownable {
    address public constant SERVICE = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    address public token;
    address public pool;
    address public borrower;

    event supplyInitiated(address indexed supplier, address indexed collateralToken, address indexed borrower);

    constructor(address _token, address _owner, address _pool, address _borrower) AbstractCallback(SERVICE) Ownable(_owner) payable {
        token = _token;
        pool = _pool;
        borrower = _borrower;
    }

    function deposit(uint256 amount) external onlyOwner {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(pool, amount);
        IPool(pool).supply(token, amount, borrower, 0);

        emit supplyInitiated(msg.sender, token, borrower);
    }

    function callback(address sender) external authorizedSenderOnly rvmIdOnly(sender) {
        IERC20(token).approve(pool, IERC20(token).balanceOf(address(this)));
        IPool(pool).supply(token, IERC20(token).balanceOf(address(this)), borrower, 0);

        emit supplyInitiated(address(this), token, borrower);
    }
}