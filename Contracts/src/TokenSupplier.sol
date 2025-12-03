// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import '../lib/reactive-lib/src/abstract-base/AbstractCallback.sol';
import '../lib/openzeppelin-contracts/contracts/access/Ownable.sol';
import '../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import './PoolInterface.sol';

contract TokenSupplier is AbstractCallback, Ownable {

    address public token;
    address public pool;
    address public borrower;

    event supplyInitiated(address token, address supplierAddress);

    constructor(address _service, address _token, address _owner, address _pool, address _borrower) AbstractCallback(_service) Ownable(_owner) payable {
        token = _token;
        pool = _pool;
        borrower = _borrower;
    }

    function deposit(uint amount) external onlyOwner {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(pool, amount);
        IPool(pool).supply(token, amount, address(this), 0);

        emit supplyInitiated(token, address(this));
    }
}