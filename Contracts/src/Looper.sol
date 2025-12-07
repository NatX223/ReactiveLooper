// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../lib/reactive-lib/src/abstract-base/AbstractCallback.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPool.sol";
import "../lib/aave-v3-core/contracts/interfaces/IPriceOracle.sol";
import "./ISwapper.sol";

contract Looper is AbstractCallback, Ownable {
    address public constant SERVICE = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    address public collateralToken;
    address public borrowToken;

    IPoolAddressesProvider public immutable ADDRESS_PROVIDER;
    IPool public immutable Pool;
    IPriceOracle public immutable priceOracle;

    ISwapper public immutable Swapper;

    uint256 private constant SAFETY_FACTOR_PERCENT = 9500;
    uint256 private constant DENOMINATOR = 10000;

    // Aave V3 Base Currency (e.g., USD) uses 8 decimals for pricing.
    uint8 private constant BASE_CURRENCY_DECIMALS = 8;

    // USDC uses 6 decimals.
    uint8 private constant BORROW_TOKEN_DECIMALS = 6;

    enum operation {
        approve,
        supply,
        borrow,
        swap
    }

    event approvalInitiated(
        address indexed approver,
        address indexed collateralToken
    );
    event supplyInitiated(
        address indexed supplier,
        address indexed collateralToken
    );
    event borrowInitiated(
        address indexed borrower,
        address indexed collateralToken,
        address indexed borrowToken
    );
    event swapInitiated(
        address indexed swapper,
        address indexed inToken,
        address indexed outToken
    );

    constructor(
        address _owner,
        address _collateralToken,
        address _borrowToken,
        address _poolAddressProvider,
        address _priceOracle,
        address _swapper
    ) payable AbstractCallback(SERVICE) Ownable(_owner) {
        collateralToken = _collateralToken;
        borrowToken = _borrowToken;

        priceOracle = IPriceOracle(_priceOracle);
        ADDRESS_PROVIDER = IPoolAddressesProvider(_poolAddressProvider);
        Pool = IPool(ADDRESS_PROVIDER.getPool());
        Swapper = ISwapper(_swapper);
    }

    function calculateSafeBorrowAmount()
        public
        view
        returns (uint256 borrowAmount)
    {
        (, , uint256 availableBorrowsBase, , , ) = Pool.getUserAccountData(
            address(this)
        );

        if (availableBorrowsBase == 0) {
            return 0;
        }

        uint256 safeBorrowsBase = (availableBorrowsBase * SAFETY_FACTOR_PERCENT) / DENOMINATOR;

        uint256 borrowTokenPriceBase = priceOracle.getAssetPrice(borrowToken);

        // Ensure price is not zero before division
        require(borrowTokenPriceBase > 0, "Price feed unavailable");

        uint256 conversionFactor = 10 ** (BASE_CURRENCY_DECIMALS - BORROW_TOKEN_DECIMALS); // 100

        // Result in 8-decimal equivalent units (e.g., 95 * 1e8 for USDC)
        uint256 tokenAmount8Decimals = (safeBorrowsBase * 10 ** BASE_CURRENCY_DECIMALS) / borrowTokenPriceBase;

        // Scale down from 8 decimals to 6 decimals (USDC standard)
        // Divides by 10^(8-6) = 100
        borrowAmount = tokenAmount8Decimals / conversionFactor;

        return borrowAmount;
    }

    function callback(
        address sender,
        uint8 _operation
    ) external authorizedSenderOnly rvmIdOnly(sender) {
        if (operation(_operation) == operation.approve) {
            IERC20(collateralToken).approve(
                address(Pool),
                IERC20(collateralToken).balanceOf(address(this))
            );
            
            emit approvalInitiated(address(this), collateralToken);
        } else if (operation(_operation) == operation.supply) {
            Pool.supply(
                collateralToken,
                IERC20(collateralToken).balanceOf(address(this)),
                address(this),
                0
            );

            emit supplyInitiated(address(this), collateralToken);
        } else if (operation(_operation) == operation.borrow) {
            uint256 borrowAmount = calculateSafeBorrowAmount();
            Pool.borrow(borrowToken, borrowAmount, 2, 0, address(this));

            emit borrowInitiated(address(this), collateralToken, borrowToken);
        } else if (operation(_operation) == operation.swap) {
            uint256 borrowTokenBalance = IERC20(borrowToken).balanceOf(
                address(this)
            );
            if (borrowTokenBalance > 0) {
                Swapper.swapAsset(borrowToken, collateralToken, borrowTokenBalance);

                emit swapInitiated(address(this), borrowToken, collateralToken);
            }
        }
    }
}
