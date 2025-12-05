// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import '../lib/reactive-lib/src/abstract-base/AbstractCallback.sol';
import '../lib/openzeppelin-contracts/contracts/access/Ownable.sol';
import '../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import '../lib/aave-v3-core/contracts/interfaces/IPool.sol';

contract TokenSupplier is AbstractCallback, Ownable {
    address public constant SERVICE = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    address public collateralToken;
    address public borrowToken;
    address public pool;
    address public borrower;

    enum operations {
        supply;
        borrow;
        swap;
    }

    event supplyInitiated(address indexed supplier, address indexed collateralToken);
    event borrowInitiated(address indexed borrower, address indexed collateralToken, address indexed borrowToken);

    constructor(address _owner, address _collateralToken, address _borrowToken, address _poolAddressProvider, address _borrower) AbstractCallback(SERVICE) Ownable(_owner) payable {
        collateralToken = _collateralToken;
        borrowToken = _borrowToken;
        pool = _pool;
        borrower = _borrower;
    }

    // function deposit(uint256 amount) external onlyOwner {
    //     IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
    //     IERC20(collateralToken).approve(pool, amount);
    //     IPool(pool).supply(collateralToken, amount, borrower, 0);

    //     emit supplyInitiated(msg.sender, collateralToken, borrower);
    // }

    function callback(address sender, uint8 operation) external authorizedSenderOnly rvmIdOnly(sender) {
        if (operation == supply) {
            IERC20(collateralToken).approve(pool, IERC20(collateralToken).balanceOf(address(this)));
            IPool(pool).supply(collateralToken, IERC20(collateralToken).balanceOf(address(this)), borrower, 0);

            emit supplyInitiated(address(this), collateralToken);
        } else if(operation == borrow) {

            // IPool(pool).borrow(borrowToken, , 2, 0, address(this));

            emit borrowInitiated(address(this), collateralToken, borrowToken);
        } else if(operation == swap) {

        }
    }
}